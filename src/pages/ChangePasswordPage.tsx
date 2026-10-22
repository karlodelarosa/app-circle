import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { KeyRound } from "lucide-react";
import { useCircles } from "../AppContext";
import { supabase } from "../lib/supabase";
import { invokeAuthenticatedFunction } from "../lib/functions";

export function ChangePasswordPage() {
  const { refresh } = useCircles(); const navigate = useNavigate();
  const [password,setPassword]=useState(""); const [confirm,setConfirm]=useState("");
  const [error,setError]=useState(""); const [busy,setBusy]=useState(false);
  const submit=async(event:FormEvent)=>{event.preventDefault();setError("");if(password!==confirm)return setError("Passwords do not match.");if(!supabase)return;setBusy(true);try{const result=await invokeAuthenticatedFunction(supabase,"circle-change-password",{password});if(result.error||result.data?.error)setError(result.data?.error||result.error?.message||"Password could not be changed.");else{await refresh();navigate("/",{replace:true});}}catch(cause){setError(cause instanceof Error?cause.message:"Password could not be changed.");}finally{setBusy(false)}};
  return <div className="mx-auto max-w-xl py-8"><KeyRound className="text-olive"/><p className="page-kicker mt-5">Secure your account</p><h1 className="mt-2 font-display text-5xl leading-tight">Choose your own password.</h1><p className="mt-4 leading-7 text-muted">Replace your temporary password before continuing to your Circle.</p><form onSubmit={submit} className="mt-8 space-y-4 paper-panel p-6"><label className="field-label">New password<input className="field" type="password" autoComplete="new-password" minLength={10} required value={password} onChange={(e)=>setPassword(e.target.value)}/></label><label className="field-label">Confirm new password<input className="field" type="password" autoComplete="new-password" minLength={10} required value={confirm} onChange={(e)=>setConfirm(e.target.value)}/></label><p className="text-xs leading-5 text-muted">Use at least 10 characters with uppercase, lowercase, and a number.</p>{error&&<p role="alert" className="form-error">{error}</p>}<button className="primary-button w-full" disabled={busy}>{busy?"Changing password…":"Change password"}</button></form></div>;
}
