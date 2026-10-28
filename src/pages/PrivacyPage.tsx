import { Link, useParams } from "react-router-dom";

export function PrivacyPage() {
  const { orgSlug = "" } = useParams();
  return (
    <main className="public-section">
      <div className="mx-auto max-w-3xl rounded-[2rem] border border-line bg-paper p-7 sm:p-10">
        <p className="page-kicker">Privacy and your choices</p>
        <h1 className="mt-2 font-display text-5xl leading-none sm:text-6xl">How Circles uses your information</h1>
        <div className="mt-8 space-y-7 leading-7 text-muted">
          <section>
            <h2 className="font-display text-3xl text-ink">Information you submit</h2>
            <p className="mt-2">An RSVP stores your name, contact details, response, and gathering. A connection request or Cell Group signup also stores the consent and placement details needed for a church leader to follow up.</p>
          </section>
          <section>
            <h2 className="font-display text-3xl text-ink">Why it is used</h2>
            <p className="mt-2">Your organization uses this information to manage attendance, respond to your request, and help you find a Cell Group. It should not be used for unrelated contact without your permission.</p>
          </section>
          <section>
            <h2 className="font-display text-3xl text-ink">Retention and security</h2>
            <p className="mt-2">Records are retained under your organization’s SheepCount privacy and retention policy, then deleted or de-identified when they are no longer required. Public forms use bot checks, rate limits, and encrypted transport.</p>
          </section>
          <section>
            <h2 className="font-display text-3xl text-ink">Access, correction, and deletion</h2>
            <p className="mt-2">Ask an organization administrator or Cell Group leader to access, correct, export, or delete information you submitted, or to withdraw your contact consent. Account and canonical People records are handled through SheepCount.</p>
          </section>
        </div>
        <Link className="secondary-button mt-9" to={`/${orgSlug}`}>Back to the community</Link>
      </div>
    </main>
  );
}
