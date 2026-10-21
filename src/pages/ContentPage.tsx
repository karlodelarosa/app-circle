import { useEffect, useRef, useState, type FormEvent } from "react";
import { CalendarDays, Images, Megaphone, Plus, Quote, X } from "lucide-react";
import { useCircles } from "../AppContext";
import { supabase } from "../lib/supabase";
import { getErrorMessage } from "../lib/errors";

type Composer = "testimony" | "gallery" | "announcement" | null;
const slugify = (value: string) =>
  value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
export function ContentPage() {
  const { data, demoMode, refresh } = useCircles();
  const [composer, setComposer] = useState<Composer>(null);
  const [form, setForm] = useState({
    title: "",
    body: "",
    author: "",
    description: "",
  });
  const [file, setFile] = useState<File | null>(null);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const dialogRef = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    if (composer && !dialogRef.current?.open) dialogRef.current?.showModal();
  }, [composer]);
  if (!data) return null;
  const publishSpace = async () => {
    if (demoMode || !supabase) {
      setMessage("Public community page is published in demo mode.");
      return;
    }
    setBusy(true);
    const { error } = await supabase.from("circle_public_spaces").upsert({
      organization_id: data.organization.id,
      introduction:
        "A welcoming place to gather, share honest stories, and grow in faith together.",
      hero_title: "There is room for you here.",
      is_published: true,
    });
    setBusy(false);
    setMessage(error ? error.message : "Community page published.");
  };
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setMessage("");
    try {
      if (!demoMode && supabase && data.group) {
        const common = {
          organization_id: data.organization.id,
          cell_group_id: data.group.id,
          created_by: data.currentUser.id,
        };
        if (composer === "testimony") {
          const { error } = await supabase.from("circle_testimonies").insert({
            ...common,
            public_slug: `${slugify(form.title)}-${Date.now().toString(36)}`,
            title: form.title,
            body: form.body,
            author_display_name: form.author,
            status: "published",
            published_at: new Date().toISOString(),
          });
          if (error) throw error;
        } else if (composer === "announcement") {
          const { error } = await supabase.from("circle_announcements").insert({
            ...common,
            title: form.title,
            body: form.body,
            published_at: new Date().toISOString(),
          });
          if (error) throw error;
        } else if (composer === "gallery") {
          let imageUrl = "";
          if (file) {
            const path = `${data.organization.id}/${crypto.randomUUID()}-${file.name.replace(/[^a-zA-Z0-9.-]/g, "-")}`;
            const upload = await supabase.storage
              .from("circle-public-media")
              .upload(path, file);
            if (upload.error) throw upload.error;
            imageUrl = supabase.storage
              .from("circle-public-media")
              .getPublicUrl(path).data.publicUrl;
          }
          const { data: gallery, error } = await supabase
            .from("circle_galleries")
            .insert({
              ...common,
              public_slug: `${slugify(form.title)}-${Date.now().toString(36)}`,
              title: form.title,
              description: form.description,
              cover_url: imageUrl || null,
              status: "published",
              published_at: new Date().toISOString(),
            })
            .select("id")
            .single();
          if (error) throw error;
          if (imageUrl) {
            const photo = await supabase.from("circle_gallery_photos").insert({
              organization_id: data.organization.id,
              gallery_id: gallery.id,
              image_url: imageUrl,
              alt_text: form.description || form.title,
              is_published: true,
            });
            if (photo.error) throw photo.error;
          }
        }
        await refresh();
      }
      setMessage(
        `${composer === "announcement" ? "Announcement" : composer === "gallery" ? "Gallery" : "Testimony"} published.`,
      );
      setComposer(null);
      setForm({ title: "", body: "", author: "", description: "" });
      setFile(null);
    } catch (c) {
      setMessage(getErrorMessage(c, "Content could not be published."));
    } finally {
      setBusy(false);
    }
  };
  return (
    <div>
      <div className="page-heading">
        <div>
          <p className="page-kicker">Community publishing</p>
          <h1>Content</h1>
          <p>
            Publish only what is meant for your organization’s public community
            space.
          </p>
        </div>
        <button
          className="secondary-button"
          disabled={busy}
          onClick={() => void publishSpace()}
        >
          {busy ? "Publishing…" : "Publish community page"}
        </button>
      </div>
      {message && !composer && (
        <p
          role="status"
          className="mt-5 rounded-xl bg-paper p-4 text-sm text-muted"
        >
          {message}
        </p>
      )}
      <div className="mt-9 grid gap-5 md:grid-cols-2">
        <ContentCard
          icon={Quote}
          title="Testimonies"
          description="Share approved stories with an intentional public author name."
          count={data.testimonies.length}
          onAdd={() => {
            setMessage("");
            setComposer("testimony");
          }}
        />
        <ContentCard
          icon={Images}
          title="Galleries"
          description="Create albums connected to gatherings and add accessible captions."
          onAdd={() => {
            setMessage("");
            setComposer("gallery");
          }}
        />
        <ContentCard
          icon={CalendarDays}
          title="Public gatherings"
          description="Visibility and guest RSVP are managed from each gathering."
          count={data.meetings.filter((m) => m.visibility === "public").length}
        />
        <ContentCard
          icon={Megaphone}
          title="Announcements"
          description="Keep members informed without creating a social feed."
          count={data.announcements.length}
          onAdd={() => {
            setMessage("");
            setComposer("announcement");
          }}
        />
      </div>
      {composer && (
        <dialog
          ref={dialogRef}
          aria-labelledby="content-composer-title"
          className="m-auto max-h-[calc(100dvh-2rem)] w-[min(42rem,calc(100%-2rem))] overflow-hidden rounded-[1.75rem] border border-line bg-paper p-0 text-ink shadow-quiet backdrop:bg-ink/55 backdrop:backdrop-blur-sm"
          onCancel={(event) => {
            event.preventDefault();
            if (!busy) setComposer(null);
          }}
          onMouseDown={(event) => {
            if (event.target === event.currentTarget && !busy)
              setComposer(null);
          }}
        >
          <form
            onSubmit={submit}
            className="flex max-h-[calc(100dvh-2rem)] flex-col"
          >
            <header className="flex items-start justify-between border-b border-line px-6 py-5 sm:px-8">
              <div>
                <p className="text-xs text-muted">Community publishing</p>
                <h2
                  id="content-composer-title"
                  className="mt-1 font-display text-3xl capitalize"
                >
                  New {composer}
                </h2>
              </div>
              <button
                type="button"
                onClick={() => setComposer(null)}
                className="icon-button"
                aria-label="Close"
                disabled={busy}
              >
                <X size={19} />
              </button>
            </header>
            <div className="space-y-4 overflow-y-auto px-6 py-6 sm:px-8">
              {message && (
                <p role="alert" className="form-error">
                  {message}
                </p>
              )}
              <label className="field-label">
                Title
                <input
                  className="field"
                  autoFocus
                  required
                  value={form.title}
                  onChange={(e) => setForm({ ...form, title: e.target.value })}
                />
              </label>
              {composer === "testimony" && (
                <>
                  <label className="field-label">
                    Public author name
                    <input
                      className="field"
                      required
                      value={form.author}
                      onChange={(e) =>
                        setForm({ ...form, author: e.target.value })
                      }
                    />
                  </label>
                  <label className="field-label">
                    Story
                    <textarea
                      className="field min-h-40"
                      required
                      value={form.body}
                      onChange={(e) =>
                        setForm({ ...form, body: e.target.value })
                      }
                    />
                  </label>
                </>
              )}
              {composer === "announcement" && (
                <label className="field-label">
                  Announcement
                  <textarea
                    className="field min-h-32"
                    required
                    value={form.body}
                    onChange={(e) => setForm({ ...form, body: e.target.value })}
                  />
                </label>
              )}
              {composer === "gallery" && (
                <>
                  <label className="field-label">
                    Description
                    <textarea
                      className="field min-h-24"
                      required
                      value={form.description}
                      onChange={(e) =>
                        setForm({ ...form, description: e.target.value })
                      }
                    />
                  </label>
                  <label className="field-label">
                    Cover photo
                    <input
                      className="field"
                      type="file"
                      accept="image/*"
                      onChange={(e) => setFile(e.target.files?.[0] || null)}
                    />
                  </label>
                </>
              )}
            </div>
            <footer className="flex justify-end gap-3 border-t border-line px-6 py-4 sm:px-8">
              <button
                type="button"
                className="secondary-button"
                onClick={() => setComposer(null)}
                disabled={busy}
              >
                Cancel
              </button>
              <button className="primary-button" disabled={busy}>
                {busy ? "Publishing…" : "Publish"}
              </button>
            </footer>
          </form>
        </dialog>
      )}
      <section className="mt-10 border-t border-line pt-8">
        <h2 className="font-display text-3xl">Publishing boundary</h2>
        <p className="mt-3 max-w-2xl leading-7 text-muted">
          People details are private by default. Content appears publicly only
          after a leader or administrator publishes that specific record.
        </p>
      </section>
    </div>
  );
}
function ContentCard({
  icon: Icon,
  title,
  description,
  count,
  onAdd,
}: {
  icon: typeof Quote;
  title: string;
  description: string;
  count?: number;
  onAdd?: () => void;
}) {
  return (
    <article className="paper-panel p-7">
      <div className="flex justify-between">
        <Icon className="text-olive" />
        {onAdd && (
          <button
            className="icon-button"
            onClick={onAdd}
            aria-label={`Add ${title}`}
          >
            <Plus />
          </button>
        )}
      </div>
      <div className="mt-8 flex items-end justify-between gap-5">
        <div>
          <h2 className="font-display text-3xl">{title}</h2>
          <p className="mt-2 text-sm leading-6 text-muted">{description}</p>
        </div>
        {count !== undefined && (
          <span className="font-display text-4xl text-olive">{count}</span>
        )}
      </div>
    </article>
  );
}
