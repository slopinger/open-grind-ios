//! UniFFI bridge between the Open Grind iOS app and the [`grindr`] transport.
//!
//! The app talks to Grindr through the same Rust transport as Open Grind on
//! Android and desktop, so requests keep the official Android app's TLS and
//! HTTP/2 fingerprint (a plain `URLSession` cannot reproduce it, and Cloudflare
//! blocks fingerprints it does not know). Everything above the transport, from
//! models to UI, lives in Swift.
//!
//! Values cross the boundary as JSON strings where they are opaque to Swift
//! (device identity, credentials, websocket payloads) and as UniFFI records
//! where Swift needs to inspect them.

use std::future::Future;
use std::sync::{Arc, LazyLock, Mutex};

use grindr::{
    AuthEvent, BanInfo, BanKind, BlockKind, Credentials, DeviceInfo, GrindrClient, GrindrError,
    MediaFetcher, MediaRequest, Method, Restriction, Session, WsConnectionState,
};
use serde::de::DeserializeOwned;
use tokio::runtime::Runtime;
use tokio::sync::broadcast::{self, error::RecvError};
use tokio::task::JoinHandle;

uniffi::setup_scaffolding!();

/// One runtime for every client: the transport spawns its websocket and token
/// refresh tasks on it, and every exported async function runs on it, so
/// Swift's executor never has to drive a tokio future.
static RUNTIME: LazyLock<Runtime> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .thread_name("opengrind-core")
        .enable_all()
        .build()
        .expect("the tokio runtime starts")
});

async fn on_runtime<T: Send + 'static>(
    future: impl Future<Output = Result<T, CoreError>> + Send + 'static,
) -> Result<T, CoreError> {
    RUNTIME.spawn(future).await.map_err(internal)?
}

/// The Grindr Android app version the transport presents as.
#[uniffi::export]
pub fn grindr_app_version() -> String {
    grindr::APP_VERSION.to_owned()
}

/// A new random device identity, as JSON. Persist it and reuse it: a stable
/// device is less likely to trip Cloudflare than a new one on every launch.
#[uniffi::export]
pub fn generate_device_json() -> String {
    serde_json::to_string(&DeviceInfo::generate()).expect("DeviceInfo serializes")
}

/// Why a call failed, mirrored from [`GrindrError`].
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    /// The request never got an answer (DNS, TCP, TLS, malformed response).
    #[error("network error: {message}")]
    Network { message: String },
    /// The request timed out.
    #[error("timed out while {phase}")]
    Timeout { phase: String },
    /// Not signed in, or the session could not be used.
    #[error("authentication error: {message}")]
    Auth { message: String },
    /// The API answered with a non-success status.
    #[error("API error {code}: {message}")]
    Api { code: i32, message: String },
    /// The API answered `401`.
    #[error("unauthorized ({code}): {message}")]
    Unauthorized { code: i32, message: String },
    /// The account, device or network is banned.
    #[error("banned: {message}")]
    Banned {
        scope: BanScope,
        code: i32,
        message: String,
        reason: Option<String>,
    },
    /// The API answered `429`.
    #[error("rate limited")]
    RateLimited,
    /// Cloudflare or another edge answered instead of the API.
    #[error("blocked before reaching the API")]
    Blocked { cloudflare: bool },
    /// An argument was malformed (bad path, JSON or content type).
    #[error("invalid request: {message}")]
    InvalidRequest { message: String },
    /// Signed out while the request was in flight.
    #[error("signed out while the request was in flight")]
    SessionCleared,
    /// A media body was larger than the limit the caller set.
    #[error("media is larger than {max_bytes} bytes")]
    MediaTooLarge { max_bytes: u64 },
    /// A bug in the bridge itself.
    #[error("internal error: {message}")]
    Internal { message: String },
}

/// What a ban applies to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum BanScope {
    Profile,
    Device,
    Network,
    Underage,
    Unknown,
}

impl From<&BanInfo> for BanScope {
    fn from(info: &BanInfo) -> Self {
        match info.kind {
            BanKind::Profile => Self::Profile,
            BanKind::Device => Self::Device,
            BanKind::Network => Self::Network,
            BanKind::Underage => Self::Underage,
            _ => Self::Unknown,
        }
    }
}

impl From<GrindrError> for CoreError {
    fn from(error: GrindrError) -> Self {
        match error {
            GrindrError::Http(message) | GrindrError::Connect(message) => Self::Network { message },
            GrindrError::Timeout(phase) => Self::Timeout {
                phase: format!("{phase:?}").to_lowercase(),
            },
            GrindrError::Auth(message) => Self::Auth { message },
            GrindrError::Api { code, message } => Self::Api { code, message },
            GrindrError::Unauthorized { code, message } => Self::Unauthorized { code, message },
            GrindrError::Banned(info) => Self::Banned {
                scope: BanScope::from(&info),
                code: info.code,
                message: info.message,
                reason: info.reason,
            },
            GrindrError::RateLimited => Self::RateLimited,
            GrindrError::Blocked(kind) => Self::Blocked {
                cloudflare: kind == BlockKind::Cloudflare,
            },
            GrindrError::InvalidRequest(message) => Self::InvalidRequest { message },
            GrindrError::SessionCleared => Self::SessionCleared,
            GrindrError::MediaTooLarge { max_bytes } => Self::MediaTooLarge {
                max_bytes: max_bytes as u64,
            },
            other => Self::Internal {
                message: other.to_string(),
            },
        }
    }
}

fn invalid(what: &str, error: impl std::fmt::Display) -> CoreError {
    CoreError::InvalidRequest {
        message: format!("{what}: {error}"),
    }
}

fn internal(error: impl std::fmt::Display) -> CoreError {
    CoreError::Internal {
        message: error.to_string(),
    }
}

/// Parses JSON from Swift; malformed input is the caller's mistake.
fn parse_json<T: DeserializeOwned>(what: &str, json: &str) -> Result<T, CoreError> {
    serde_json::from_str(json).map_err(|e| invalid(what, e))
}

/// Calls `forward` with every value sent on `receiver` until it closes,
/// skipping over values missed while the listener lagged behind.
fn forward_each<T: Clone + Send + 'static>(
    mut receiver: broadcast::Receiver<T>,
    forward: impl Fn(T) + Send + 'static,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        loop {
            match receiver.recv().await {
                Ok(value) => forward(value),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => break,
            }
        }
    })
}

/// An account restriction carried in the session. The session stays valid.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum AccountRestriction {
    AgeVerification {
        region: String,
    },
    TimedBan {
        expires_at: Option<i64>,
        reason: Option<String>,
    },
    TrustVendorRejected,
    Other {
        value: String,
    },
}

impl From<Restriction> for AccountRestriction {
    fn from(restriction: Restriction) -> Self {
        match restriction {
            Restriction::AgeVerification { region, .. } => Self::AgeVerification {
                region: format!("{region:?}"),
            },
            Restriction::TimedBan(details) => Self::TimedBan {
                expires_at: details.expiry_time,
                reason: details.reason,
            },
            Restriction::TrustVendorRejected => Self::TrustVendorRejected,
            Restriction::Other(value) => Self::Other { value },
            other => Self::Other {
                value: format!("{other:?}"),
            },
        }
    }
}

/// The result of a successful sign-in.
#[derive(Debug, Clone, uniffi::Record)]
pub struct SignInOutcome {
    pub profile_id: String,
    pub restriction: Option<AccountRestriction>,
}

/// A request body.
#[derive(Debug, Clone, uniffi::Enum)]
pub enum RequestBody {
    Empty,
    /// A JSON document, sent with the app's JSON content type.
    Json {
        json: String,
    },
    /// Raw bytes, e.g. an image upload.
    Bytes {
        content_type: String,
        bytes: Vec<u8>,
    },
}

/// An API response, whatever its status.
#[derive(Debug, Clone, uniffi::Record)]
pub struct HttpResponse {
    pub status: u16,
    pub body: Vec<u8>,
}

/// A CDN response.
#[derive(Debug, Clone, uniffi::Record)]
pub struct MediaResult {
    pub status: u16,
    pub content_type: Option<String>,
    pub body: Vec<u8>,
}

/// A change in the session that the app may have to react to.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum AuthNotice {
    /// The server ended the session; sign in again.
    SignedOut,
    /// The account was banned and the session cleared.
    Banned {
        message: String,
        reason: Option<String>,
    },
}

impl AuthNotice {
    fn from_event(event: AuthEvent) -> Option<Self> {
        Some(match event {
            AuthEvent::SignedOut => Self::SignedOut,
            AuthEvent::Banned(info) => Self::Banned {
                message: info.message,
                reason: info.reason,
            },
            // Refresh failures keep the session; the transport retries them.
            _ => return None,
        })
    }
}

/// Receives the client's background state. Called from background threads.
#[uniffi::export(with_foreign)]
pub trait CoreListener: Send + Sync {
    /// The durable credentials changed (sign-in, sign-out, refresh). `None`
    /// means signed out: delete what was stored.
    fn credentials_changed(&self, credentials_json: Option<String>);
    /// A websocket event; `event_json` is the whole event including `type`.
    fn websocket_event(&self, event_type: String, event_json: String);
    /// The websocket connected or disconnected.
    fn websocket_state_changed(&self, connected: bool);
    /// The session changed in the background.
    fn auth_notice(&self, notice: AuthNotice);
}

/// A Grindr client: session, REST, media and the realtime websocket.
#[derive(uniffi::Object)]
pub struct CoreClient {
    client: GrindrClient,
    listener_tasks: Mutex<Vec<JoinHandle<()>>>,
}

impl Drop for CoreClient {
    fn drop(&mut self) {
        self.stop_listening();
    }
}

impl CoreClient {
    fn stop_listening(&self) {
        let tasks = std::mem::take(&mut *self.listener_tasks.lock().expect("listener lock"));
        for task in tasks {
            task.abort();
        }
    }
}

#[uniffi::export]
impl CoreClient {
    /// Creates a client for `device_json` (see [`generate_device_json`]),
    /// resuming the account in `credentials_json` if given.
    #[uniffi::constructor]
    pub fn new(
        device_json: String,
        credentials_json: Option<String>,
    ) -> Result<Arc<Self>, CoreError> {
        let device: DeviceInfo = parse_json("device", &device_json)?;
        let session = credentials_json
            .map(|json| parse_json::<Credentials>("credentials", &json))
            .transpose()?
            .map(|credentials| Session {
                credentials,
                token: None,
            });
        let client = GrindrClient::new(device, session)?;
        Ok(Arc::new(Self {
            client,
            listener_tasks: Mutex::new(Vec::new()),
        }))
    }

    /// Forwards the client's background state to `listener`, replacing any
    /// previous listener. Reports the current credentials and connection
    /// state right away.
    pub fn set_listener(&self, listener: Arc<dyn CoreListener>) {
        self.stop_listening();
        let _guard = RUNTIME.enter();
        let mut tasks = Vec::with_capacity(4);

        let mut sessions = self.client.session_receiver();
        let target = Arc::clone(&listener);
        tasks.push(tokio::spawn(async move {
            let mut last: Option<String> = None;
            loop {
                let current = sessions
                    .borrow_and_update()
                    .as_ref()
                    .and_then(|session| serde_json::to_string(&session.credentials).ok());
                // Token refreshes re-send unchanged credentials; skip those.
                if current != last || current.is_none() {
                    target.credentials_changed(current.clone());
                    last = current;
                }
                if sessions.changed().await.is_err() {
                    break;
                }
            }
        }));

        let target = Arc::clone(&listener);
        tasks.push(forward_each(self.client.ws_receiver(), move |event| {
            target.websocket_event(event.event_type, event.payload.to_string())
        }));

        let mut states = self.client.connection_state();
        let target = Arc::clone(&listener);
        tasks.push(tokio::spawn(async move {
            loop {
                let connected = *states.borrow_and_update() == WsConnectionState::Connected;
                target.websocket_state_changed(connected);
                if states.changed().await.is_err() {
                    break;
                }
            }
        }));

        tasks.push(forward_each(
            self.client.auth_event_receiver(),
            move |event| {
                if let Some(notice) = AuthNotice::from_event(event) {
                    listener.auth_notice(notice);
                }
            },
        ));

        *self.listener_tasks.lock().expect("listener lock") = tasks;
    }

    /// Signs in with email and password. `geohash` tags the sign-in with an
    /// approximate location.
    pub async fn sign_in_with_email(
        &self,
        email: String,
        password: String,
        geohash: Option<String>,
    ) -> Result<SignInOutcome, CoreError> {
        let client = self.client.clone();
        on_runtime(async move {
            let result = client
                .sign_in_with_email_at_geohash(&email, &password, geohash.as_deref())
                .await?;
            Ok(SignInOutcome {
                profile_id: result.profile_id,
                restriction: result.restriction.map(AccountRestriction::from),
            })
        })
        .await
    }

    /// Ends the session and closes the websocket. With `new_device_json`, the
    /// device identity and transport are replaced too, so the next sign-in
    /// cannot be correlated with this one.
    pub async fn sign_out(&self, new_device_json: Option<String>) -> Result<(), CoreError> {
        let device = new_device_json
            .map(|json| parse_json::<DeviceInfo>("device", &json))
            .transpose()?;
        let client = self.client.clone();
        on_runtime(async move {
            match device {
                Some(device) => {
                    client.sign_out_rotating(device).await?;
                }
                None => client.sign_out().await,
            }
            Ok(())
        })
        .await
    }

    /// Sends a request to `path` (which must start with `/`), with the
    /// session unless `authenticated` is false.
    pub async fn request(
        &self,
        method: String,
        path: String,
        body: RequestBody,
        authenticated: bool,
    ) -> Result<HttpResponse, CoreError> {
        let method = Method::from_bytes(method.as_bytes()).map_err(|e| invalid("method", e))?;
        let mut builder = self.client.request(method, &path);
        builder = match body {
            RequestBody::Empty => builder,
            RequestBody::Json { json } => {
                builder.json(&parse_json::<serde_json::Value>("body", &json)?)
            }
            RequestBody::Bytes {
                content_type,
                bytes,
            } => builder.bytes(&content_type, bytes),
        };
        if !authenticated {
            builder = builder.unauthenticated();
        }
        on_runtime(async move {
            let response = builder.send().await?;
            Ok(HttpResponse {
                status: response.status,
                body: response.body,
            })
        })
        .await
    }

    /// Downloads a CDN file (`cdns.grindr.com`, CloudFront or GIPHY) with the
    /// app's image loader headers. Fails if the body exceeds `max_bytes`.
    pub async fn fetch_media(&self, url: String, max_bytes: u64) -> Result<MediaResult, CoreError> {
        let client = self.client.clone();
        on_runtime(async move {
            let response = client
                .fetch_media(MediaRequest {
                    url: &url,
                    range: None,
                    max_bytes: usize::try_from(max_bytes).unwrap_or(usize::MAX),
                    fetcher: MediaFetcher::ImageLoader,
                })
                .await?;
            Ok(MediaResult {
                status: response.status,
                content_type: response.content_type,
                // Reuses the buffer when nothing else holds it.
                body: Vec::from(response.body),
            })
        })
        .await
    }

    /// Opts in to the realtime websocket. It connects whenever a session
    /// exists and reconnects on its own.
    pub async fn connect(&self) -> Result<(), CoreError> {
        let client = self.client.clone();
        on_runtime(async move {
            client.connect().await;
            Ok(())
        })
        .await
    }

    /// Follows the app between foreground (`true`) and background, so token
    /// refreshes and reconnects pause while the app is suspended.
    pub fn set_active(&self, active: bool) {
        self.client.set_active(active);
    }
}

#[cfg(test)]
mod tests {
    use std::sync::mpsc;
    use std::time::Duration;

    use super::*;

    struct Recorder(Mutex<mpsc::Sender<Option<String>>>);

    impl CoreListener for Recorder {
        fn credentials_changed(&self, credentials_json: Option<String>) {
            self.0.lock().unwrap().send(credentials_json).unwrap();
        }
        fn websocket_event(&self, _: String, _: String) {}
        fn websocket_state_changed(&self, _: bool) {}
        fn auth_notice(&self, _: AuthNotice) {}
    }

    fn credentials() -> String {
        r#"{"email":"ada@example.com","profile_id":"42","auth_token":"secret","kind":"Email"}"#
            .to_owned()
    }

    #[test]
    fn generated_devices_round_trip_through_json() {
        let json = generate_device_json();
        let device: DeviceInfo = serde_json::from_str(&json).unwrap();
        assert_eq!(device.device_id.len(), 16);
        assert!(CoreClient::new(json, None).is_ok());
    }

    #[test]
    fn malformed_device_or_credentials_are_invalid_requests() {
        assert!(matches!(
            CoreClient::new("{}".into(), None),
            Err(CoreError::InvalidRequest { .. })
        ));
        assert!(matches!(
            CoreClient::new(generate_device_json(), Some("nope".into())),
            Err(CoreError::InvalidRequest { .. })
        ));
    }

    #[test]
    fn the_listener_hears_resumed_credentials_then_the_sign_out() {
        let client = CoreClient::new(generate_device_json(), Some(credentials())).unwrap();
        let (tx, rx) = mpsc::channel();
        client.set_listener(Arc::new(Recorder(Mutex::new(tx))));

        let first = rx.recv_timeout(Duration::from_secs(5)).unwrap().unwrap();
        let resumed: Credentials = serde_json::from_str(&first).unwrap();
        assert_eq!(resumed.auth_token, "secret");
        assert_eq!(resumed.profile_id.as_deref(), Some("42"));

        RUNTIME.block_on(client.sign_out(None)).unwrap();
        assert_eq!(rx.recv_timeout(Duration::from_secs(5)).unwrap(), None);
    }

    #[test]
    fn a_path_without_a_leading_slash_never_leaves_the_device() {
        let client = CoreClient::new(generate_device_json(), None).unwrap();
        let result = RUNTIME.block_on(client.request(
            "GET".into(),
            "evil.example/v3/me".into(),
            RequestBody::Empty,
            false,
        ));
        assert!(
            matches!(result, Err(CoreError::InvalidRequest { .. })),
            "{result:?}"
        );
    }

    #[test]
    fn a_malformed_json_body_is_rejected_before_sending() {
        let client = CoreClient::new(generate_device_json(), None).unwrap();
        let result = RUNTIME.block_on(client.request(
            "POST".into(),
            "/v4/location".into(),
            RequestBody::Json { json: "{".into() },
            true,
        ));
        assert!(
            matches!(result, Err(CoreError::InvalidRequest { .. })),
            "{result:?}"
        );
    }

    #[test]
    fn errors_keep_what_the_app_needs_to_explain_them() {
        assert!(matches!(
            CoreError::from(GrindrError::RateLimited),
            CoreError::RateLimited
        ));
        assert!(matches!(
            CoreError::from(GrindrError::Blocked(BlockKind::Cloudflare)),
            CoreError::Blocked { cloudflare: true }
        ));
        assert!(matches!(
            CoreError::from(GrindrError::Api {
                code: 404,
                message: "gone".into()
            }),
            CoreError::Api { code: 404, .. }
        ));
    }
}
