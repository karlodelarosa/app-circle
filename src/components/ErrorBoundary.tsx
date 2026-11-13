import { Component, type ErrorInfo, type ReactNode } from "react";
import { reportClientError } from "../lib/telemetry";

interface Props {
  children: ReactNode;
  onReload?: () => void;
}

export class ErrorBoundary extends Component<Props, { failed: boolean }> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  componentDidCatch(error: Error, _info: ErrorInfo) {
    reportClientError(error);
  }

  render() {
    if (!this.state.failed) return this.props.children;
    return (
      <main className="grid min-h-screen place-items-center bg-parchment p-6 text-ink">
        <div className="max-w-md text-center">
          <p className="page-kicker">Unexpected error</p>
          <h1 className="mt-2 font-display text-4xl">Circles hit an unexpected problem.</h1>
          <p className="mt-4 leading-7 text-muted">Your information was not included in the error report. Reload the app to try again.</p>
          <button className="primary-button mt-6" onClick={this.props.onReload ?? (() => window.location.reload())}>
            Reload Circles
          </button>
        </div>
      </main>
    );
  }
}
