import {
  CalendarDays,
  ChevronDown,
  CircleUserRound,
  FileText,
  Home,
  HeartHandshake,
  LogIn,
  LogOut,
  WifiOff,
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Link, NavLink, Outlet } from "react-router-dom";
import { useCircles } from "../AppContext";
import { Avatar } from "./Avatar";

export function Brand() {
  return (
    <div className="flex items-center gap-3">
      <img
        src="/circles-logo.png"
        alt=""
        className="h-11 w-11 object-contain"
      />
      <div>
        <div className="font-display text-[1.7rem] leading-none">Circles</div>
        <div className="mt-1 text-[10px] tracking-[0.12em] text-muted">
          Grow together
        </div>
      </div>
    </div>
  );
}

function AccountMenu({
  person,
  demoMode,
  signOut,
}: {
  person: { id: string; fullName: string; avatarUrl?: string; role: string };
  demoMode: boolean;
  signOut: () => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const closeOnOutside = (event: PointerEvent) => {
      if (!menuRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("pointerdown", closeOnOutside);
    document.addEventListener("keydown", closeOnEscape);
    return () => {
      document.removeEventListener("pointerdown", closeOnOutside);
      document.removeEventListener("keydown", closeOnEscape);
    };
  }, [open]);

  return (
    <div className="relative" ref={menuRef}>
      <button
        type="button"
        className="flex min-h-11 items-center gap-3 rounded-xl px-2 py-1.5 text-left hover:bg-paper focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-olive"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
      >
        <Avatar person={person} />
        <span className="hidden min-w-0 sm:block">
          <span className="block max-w-44 truncate text-sm font-medium">
            {person.fullName}
          </span>
          <span className="block text-xs capitalize text-muted">
            {person.role}
          </span>
        </span>
        <ChevronDown
          size={15}
          className={`hidden text-muted transition-transform sm:block ${open ? "rotate-180" : ""}`}
        />
      </button>
      {open && (
        <div
          role="menu"
          className="absolute right-0 top-[calc(100%+.5rem)] z-50 min-w-56 rounded-2xl border border-line bg-paper p-2 shadow-quiet"
        >
          <div className="border-b border-line px-3 py-2 sm:hidden">
            <p className="truncate text-sm font-medium">{person.fullName}</p>
            <p className="mt-0.5 text-xs capitalize text-muted">
              {person.role}
            </p>
          </div>
          {demoMode ? (
            <>
              <p className="px-3 py-2 text-xs text-muted">Demo session</p>
              <Link
                to="/sign-in?next=/"
                role="menuitem"
                className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm hover:bg-parchment focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-olive"
                onClick={() => setOpen(false)}
              >
                <LogIn size={16} />
                Sign in with SheepCount
              </Link>
            </>
          ) : (
            <button
              type="button"
              role="menuitem"
              className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm hover:bg-parchment focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-olive"
              onClick={() => void signOut()}
            >
              <LogOut size={16} />
              Sign out
            </button>
          )}
        </div>
      )}
    </div>
  );
}

export function AppShell() {
  const { data, demoMode, signOut, toast } = useCircles();
  if (!data) return null;
  const base = "/";
  const canLead =
    data.currentUser.role === "admin" ||
    data.groups.some((g) => g.role === "leader");
  const links = [
    { to: base, label: "Dashboard", mobileLabel: "Home", icon: Home },
    { to: "/circles", label: "My Circles", mobileLabel: "Circles", icon: CircleUserRound },
    { to: "/gatherings", label: "Gatherings", mobileLabel: "Gatherings", icon: CalendarDays },
    ...(canLead
      ? [
          {
            to: "/connections",
            label: "Guest connections",
            mobileLabel: "Guests",
            icon: HeartHandshake,
            badge: data.connectionAttentionCount,
          },
          { to: "/content", label: "Publish", mobileLabel: "Publish", icon: FileText },
        ]
      : []),
  ];
  return (
    <div className="min-h-screen bg-parchment text-ink">
      <aside className="fixed inset-y-0 left-0 z-20 hidden w-64 border-r border-line bg-paper/95 px-6 py-7 lg:flex lg:flex-col">
        <Link to="/">
          <Brand />
        </Link>
        <div className="mt-10 border-t border-line pt-5">
          <div className="text-xs text-muted">{data.organization.name}</div>
          <div className="mt-2 font-display text-xl">Your community</div>
        </div>
        <nav className="mt-5 space-y-1" aria-label="Main navigation">
          {links.map(({ to, label, icon: Icon, ...item }) => (
            <NavLink
              key={to}
              to={to}
              end={to === base}
              className={({ isActive }) =>
                `nav-link ${isActive ? "nav-link-active" : ""}`
              }
            >
              <Icon size={18} />
              {label}
              {"badge" in item && item.badge ? (
                <span className="ml-auto rounded-full bg-paper px-2 py-0.5 text-[10px] text-olive">
                  {item.badge}
                </span>
              ) : null}
            </NavLink>
          ))}
        </nav>
      </aside>
      <div className="lg:pl-64">
        <header className="sticky top-0 z-10 flex h-[72px] items-center justify-between border-b border-line/80 bg-parchment/90 px-5 backdrop-blur-md lg:px-10">
          <div className="lg:hidden">
            <Brand />
          </div>
          <p className="hidden text-sm text-muted lg:block">
            Participation, not administration.
          </p>
          <div className="flex items-center gap-3">
            {demoMode && (
              <span className="hidden items-center gap-1.5 rounded-full bg-paper px-3 py-1.5 text-xs text-muted ring-1 ring-line sm:flex">
                <WifiOff size={13} /> Demo mode
              </span>
            )}
            <AccountMenu
              person={data.currentUser}
              demoMode={demoMode}
              signOut={signOut}
            />
          </div>
        </header>
        <main className="mx-auto max-w-6xl px-4 pb-28 pt-5 sm:px-6 lg:px-10 lg:pb-12 lg:pt-8">
          <Outlet />
        </main>
      </div>
      <nav
        className={`fixed inset-x-0 bottom-0 z-30 grid border-t border-line bg-paper/95 px-1 pb-[max(0.5rem,env(safe-area-inset-bottom))] pt-2 backdrop-blur-md lg:hidden ${canLead ? "grid-cols-5" : "grid-cols-3"}`}
        aria-label="Main navigation"
      >
        {links.map(({ to, mobileLabel, icon: Icon, ...item }) => (
          <NavLink
            key={to}
            to={to}
            end={to === base}
            className={({ isActive }) =>
              `mobile-nav-link relative ${isActive ? "text-olive" : "text-muted"}`
            }
          >
            <Icon size={20} />
            <span>{mobileLabel}</span>
            {"badge" in item && item.badge ? (
              <span className="absolute right-[22%] top-0 grid h-4 min-w-4 place-items-center rounded-full bg-olive px-1 text-[9px] text-paper">
                {item.badge}
              </span>
            ) : null}
          </NavLink>
        ))}
      </nav>
      {toast && (
        <div
          role="status"
          className="fixed bottom-24 left-1/2 z-[60] -translate-x-1/2 rounded-full bg-ink px-5 py-3 text-sm text-paper shadow-quiet"
        >
          {toast}
        </div>
      )}
    </div>
  );
}
