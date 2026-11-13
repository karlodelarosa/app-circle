import { KeyRound, Mail } from "lucide-react";
import { useState, type FormEvent } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Brand } from "../components/AppShell";
import { supabase } from "../lib/supabase";
import { validatePassword } from "../lib/password";

export function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    if (supabase) {
      await supabase.auth.resetPasswordForEmail(email.trim().toLowerCase(), {
        redirectTo: `${window.location.origin}/reset-password`,
      });
    }
    setSent(true);
    setBusy(false);
  };
  return <main className="grid min-h-screen place-items-center bg-parchment p-6"><div className="w-full max-w-md"><Brand/><div className="mt-14 rounded-[2rem] border border-line bg-paper p-7 sm:p-9"><Mail className="text-olive"/><h1 className="mt-5 font-display text-5xl leading-none">Recover your account</h1>{sent?<div className="mt-6" role="status"><p className="leading-7 text-muted">If that email has a SheepCount account, a password-reset link is on its way.</p><Link className="secondary-button mt-6" to="/sign-in">Return to sign in</Link></div>:<><p className="mt-4 leading-7 text-muted">Email accounts can receive a secure reset link. For a generated Member ID, ask your Circle leader to issue a new temporary password.</p><form className="mt-7 space-y-4" onSubmit={submit}><label className="field-label">SheepCount email<input className="field" type="email" required autoComplete="email" value={email} onChange={(event)=>setEmail(event.target.value)}/></label><button className="primary-button w-full" disabled={busy}>{busy?"Sending…":"Send reset link"}</button></form></>} </div></div></main>;
}

export function ResetPasswordPage() {
  const navigate = useNavigate();
  const [password,setPassword]=useState("");
  const [confirm,setConfirm]=useState("");
  const [error,setError]=useState("");
  const [busy,setBusy]=useState(false);
  const submit=async(event:FormEvent)=>{event.preventDefault();setError("");const requirement=validatePassword(password);if(requirement)return setError(requirement);if(password!==confirm)return setError("The passwords do not match.");if(!supabase)return setError("Password recovery is unavailable.");setBusy(true);const result=await supabase.auth.updateUser({password});setBusy(false);if(result.error)return setError("This reset link is invalid or has expired. Request a new one.");navigate("/sign-in",{replace:true});};
  return <main className="grid min-h-screen place-items-center bg-parchment p-6"><div className="w-full max-w-md"><Brand/><form className="mt-14 rounded-[2rem] border border-line bg-paper p-7 sm:p-9" onSubmit={submit}><KeyRound className="text-olive"/><h1 className="mt-5 font-display text-5xl leading-none">Choose a new password</h1><p className="mt-4 leading-7 text-muted">Use at least 10 characters with uppercase, lowercase, and a number.</p><div className="mt-7 space-y-4"><label className="field-label">New password<input className="field" type="password" minLength={10} required autoComplete="new-password" value={password} onChange={(event)=>setPassword(event.target.value)}/></label><label className="field-label">Confirm password<input className="field" type="password" minLength={10} required autoComplete="new-password" value={confirm} onChange={(event)=>setConfirm(event.target.value)}/></label>{error&&<p className="form-error" role="alert">{error}</p>}<button className="primary-button w-full" disabled={busy}>{busy?"Saving…":"Save new password"}</button></div></form></div></main>;
}
