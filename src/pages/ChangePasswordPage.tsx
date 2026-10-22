import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { KeyRound } from "lucide-react";
import { useCircles } from "../AppContext";
import { supabase } from "../lib/supabase";
import { getFunctionErrorMessage, invokeAuthenticatedFunction } from "../lib/functions";
import { validatePassword } from "../lib/password";

export function ChangePasswordPage() {
  const { refresh } = useCircles();
  const navigate = useNavigate();
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [showPasswords, setShowPasswords] = useState(false);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setError("");
    const requirementError = validatePassword(password);
    if (requirementError) return setError(requirementError);
    if (password !== confirm) {
      return setError("The passwords do not match. Re-enter the confirmation password.");
    }
    if (!supabase) return;

    setBusy(true);
    try {
      const result = await invokeAuthenticatedFunction(
        supabase,
        "circle-change-password",
        { password },
      );
      if (result.error || result.data?.error) {
        setError(await getFunctionErrorMessage(
          result,
          "Password could not be changed. Check the requirements and try again.",
        ));
      } else {
        await refresh();
        navigate("/", { replace: true });
      }
    } catch (cause) {
      const message = cause instanceof Error ? cause.message : "";
      setError(
        message && !message.toLowerCase().includes("non-2xx status code")
          ? message
          : "Password could not be changed. Check the requirements and try again.",
      );
    } finally {
      setBusy(false);
    }
  };

  const passwordType = showPasswords ? "text" : "password";

  return (
    <div className="mx-auto max-w-xl py-8">
      <KeyRound className="text-olive" />
      <p className="page-kicker mt-5">Secure your account</p>
      <h1 className="mt-2 font-display text-5xl leading-tight">Choose your own password.</h1>
      <p className="mt-4 leading-7 text-muted">Replace your temporary password before continuing to your Circle.</p>
      <form onSubmit={submit} className="mt-8 space-y-4 paper-panel p-6">
        <div id="password-requirements" className="rounded-xl bg-parchment p-4 text-sm leading-6 text-muted">
          <strong className="block text-ink">Your new password must include:</strong>
          <ul className="mt-1 list-disc pl-5">
            <li>At least 10 characters</li>
            <li>One uppercase letter</li>
            <li>One lowercase letter</li>
            <li>One number</li>
          </ul>
        </div>
        <label className="field-label">
          New password
          <input className="field" type={passwordType} autoComplete="new-password" aria-describedby="password-requirements" minLength={10} required value={password} onChange={(event) => setPassword(event.target.value)} />
        </label>
        <label className="field-label">
          Confirm new password
          <input className="field" type={passwordType} autoComplete="new-password" minLength={10} required value={confirm} onChange={(event) => setConfirm(event.target.value)} />
        </label>
        <label className="flex min-h-11 cursor-pointer items-center gap-3 text-sm font-medium text-ink">
          <input className="h-5 w-5 accent-olive" type="checkbox" checked={showPasswords} onChange={(event) => setShowPasswords(event.target.checked)} />
          Show passwords
        </label>
        {error && <p role="alert" className="form-error">{error}</p>}
        <button className="primary-button w-full" disabled={busy}>{busy ? "Changing password…" : "Change password"}</button>
      </form>
    </div>
  );
}
