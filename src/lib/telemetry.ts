export function reportClientError(error: unknown) {
  const payload = {
    event: "react_error_boundary",
    errorType: error instanceof Error ? error.name : "UnknownError",
    path: window.location.pathname,
  };
  void fetch("/__telemetry/client-error", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
    keepalive: true,
  }).catch(() => undefined);
}
