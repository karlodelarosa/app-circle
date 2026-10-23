import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import type { Session } from "@supabase/supabase-js";
import { isSupabaseConfigured, supabase } from "./lib/supabase";
import { getErrorMessage } from "./lib/errors";
import * as api from "./services/circles";
import type { AppData, MeetingInput, PrayerInput, RsvpStatus } from "./types";

interface AppContextValue {
  data: AppData | null;
  session: Session | null;
  loading: boolean;
  error: string | null;
  demoMode: boolean;
  toast: string | null;
  refresh: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  selectGroup: (groupId: string) => Promise<void>;
  createGroup: (input: {
    name: string;
    description: string;
    location: string;
    leaderPersonId?: string;
  }) => Promise<void>;
  setRsvp: (meetingId: string, status: RsvpStatus) => Promise<void>;
  addPrayer: (input: PrayerInput) => Promise<void>;
  togglePrayer: (prayerId: string) => Promise<void>;
  markAnswered: (prayerId: string, notes: string) => Promise<void>;
  saveMeeting: (input: MeetingInput, id?: string) => Promise<void>;
  cancelMeeting: (id: string) => Promise<void>;
  requestMemberAccess: (personId: string) => Promise<void>;
  removeMember: (membershipId: string) => Promise<void>;
  openCheckin: (meetingId: string) => Promise<string>;
  closeCheckin: (meetingId: string) => Promise<void>;
}

const AppContext = createContext<AppContextValue | null>(null);

export function AppProvider({
  children,
  initialData = null,
  initialSession = null,
}: {
  children: ReactNode;
  initialData?: AppData | null;
  initialSession?: Session | null;
}) {
  const [data, setData] = useState<AppData | null>(initialData);
  const [session, setSession] = useState<Session | null>(initialSession);
  const [selectedGroupId, setSelectedGroupId] = useState<string>();
  const [loading, setLoading] = useState(
    isSupabaseConfigured && !initialSession,
  );
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const authenticatedUserRef = useRef<string>();

  const notify = useCallback((message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(null), 2800);
  }, []);

  const sessionUserId = session?.user.id;
  const sessionEmail = session?.user.email ?? "";
  const refresh = useCallback(async () => {
    if (!supabase || !sessionUserId) return;
    setError(null);
    try {
      const next = await api.loadAppData(
        supabase,
        sessionUserId,
        selectedGroupId,
      );
      next.currentUser.email = sessionEmail;
      setData(next);
      setSelectedGroupId(next.group?.id);
    } catch (cause) {
      setError(
        !navigator.onLine
          ? "You’re offline. The Circles shell is available, but private group data needs a connection. Reconnect and try again."
          : getErrorMessage(cause, "Circles could not load your group."),
      );
    } finally {
      setLoading(false);
    }
  }, [sessionUserId, sessionEmail, selectedGroupId]);

  useEffect(() => {
    if (!supabase) return;
    const { data: listener } = supabase.auth.onAuthStateChange(
      (_event, nextSession) => {
        const nextUserId = nextSession?.user.id;
        const identityChanged = authenticatedUserRef.current !== nextUserId;
        authenticatedUserRef.current = nextUserId;
        setSession(nextSession);
        if (nextSession) {
          if (identityChanged) {
            setData(null);
            setSelectedGroupId(undefined);
            setError(null);
            setLoading(true);
          }
        } else {
          setData(null);
          setSelectedGroupId(undefined);
          setError(null);
          setLoading(false);
        }
      },
    );
    return () => listener.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (sessionUserId) void refresh();
    // A refreshed token creates a new Session object. Reload only when the
    // authenticated identity changes, not when the tab regains focus.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessionUserId]);

  const requirePerson = () => {
    const personId = data?.currentUser.personId;
    if (!personId)
      throw new Error(
        "Your administrator account is not linked to a directory person. Link it before participating as a member.",
      );
    return personId;
  };

  const signIn = async (email: string, password: string) => {
    if (!supabase)
      throw new Error(
        "Live sign-in is not configured for this deployment. Add the Supabase build variables in Cloudflare and redeploy.",
      );
    const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (authError) throw authError;
    if (!authData.session)
      throw new Error("SheepCount signed in without starting a session.");
    setLoading(true);
    setError(null);
    try {
      const next = await api.loadAppData(
        supabase,
        authData.session.user.id,
        selectedGroupId,
      );
      next.currentUser.email = authData.session.user.email ?? "";
      setSession(authData.session);
      setData(next);
      setSelectedGroupId(next.group?.id);
      notify("Signed in with SheepCount.");
    } catch (cause) {
      await supabase.auth.signOut({ scope: "local" });
      setSession(null);
      setData(null);
      setSelectedGroupId(undefined);
      setError(null);
      throw cause;
    } finally {
      setLoading(false);
    }
  };

  const signOut = async () => {
    if (supabase) await supabase.auth.signOut({ scope: "local" });
    authenticatedUserRef.current = undefined;
  };

  const selectGroup = async (groupId: string) => {
    setSelectedGroupId(groupId);
    if (supabase && session?.user) {
      setError(null);
      try {
        const next = await api.loadAppData(supabase, session.user.id, groupId);
        next.currentUser.email = session.user.email ?? "";
        setData(next);
        setSelectedGroupId(next.group?.id);
      } catch (cause) {
        setError(getErrorMessage(cause, "Circles could not load that group."));
      }
    } else if (data) {
      const group =
        data.groups.find((item) => item.id === groupId) ?? data.group;
      setData({ ...data, group });
    }
  };

  const createGroup = async (input: {
    name: string;
    description: string;
    location: string;
    leaderPersonId?: string;
  }) => {
    if (!data) return;
    if (supabase && session) {
      const id = await api.createGroup(supabase, input);
      if (!session?.user) return;
      const next = await api.loadAppData(supabase, session.user.id, id);
      next.currentUser.email = session.user.email ?? "";
      setData(next);
      setSelectedGroupId(id);
    } else {
      const group = {
        id: crypto.randomUUID(),
        organizationId: data.organization.id,
        regularSchedule: "",
        role: "admin" as const,
        leaderId: input.leaderPersonId,
        ...input,
      };
      setData({ ...data, groups: [...data.groups, group], group });
    }
    notify("Cell group created in SheepCount.");
  };

  const setRsvp = async (meetingId: string, status: RsvpStatus) => {
    if (!data) return;
    const personId = requirePerson();
    const previous = data;
    setData({
      ...data,
      meetings: data.meetings.map((meeting) =>
        meeting.id === meetingId
          ? { ...meeting, rsvps: { ...meeting.rsvps, [personId]: status } }
          : meeting,
      ),
      accessibleMeetings: data.accessibleMeetings?.map((meeting) =>
        meeting.id === meetingId
          ? { ...meeting, rsvps: { ...meeting.rsvps, [personId]: status } }
          : meeting,
      ),
      dashboard: data.dashboard
        ? {
            ...data.dashboard,
            meetings: data.dashboard.meetings.map((meeting) =>
              meeting.id === meetingId
                ? { ...meeting, rsvps: { ...meeting.rsvps, [personId]: status } }
                : meeting,
            ),
          }
        : undefined,
    });
    try {
      if (supabase && session)
        await api.saveRsvp(
          supabase,
          data.organization.id,
          meetingId,
          personId,
          status,
        );
      notify(
        status === "attending"
          ? "You’re going."
          : status === "tentative"
            ? "Marked as maybe."
            : "RSVP updated.",
      );
    } catch (cause) {
      setData(previous);
      throw cause;
    }
  };

  const addPrayer = async (input: PrayerInput) => {
    if (!data) return;
    if (input.scope === "circle" && !data.group)
      throw new Error("Select a Circle before sharing with My Circle.");
    const personId = requirePerson();
    const groupId = input.scope === "circle" ? data.group?.id : undefined;
    const destinationName =
      input.scope === "organization"
        ? "Entire organization"
        : data.group?.name;
    if (supabase && session) {
      await api.createPrayer(
        supabase,
        data.organization.id,
        groupId,
        personId,
        input,
      );
      await refresh();
    } else {
      setData({
        ...data,
        prayers: [
          {
            id: crypto.randomUUID(),
            groupId,
            userId: personId,
            authorName: data.currentUser.fullName,
            destinationName,
            ...input,
            isAnswered: false,
            createdAt: new Date().toISOString(),
            prayerCount: 0,
            prayedByMe: false,
          },
          ...data.prayers,
        ],
      });
    }
    notify(`Prayer shared with ${destinationName}.`);
  };

  const togglePrayer = async (prayerId: string) => {
    if (!data) return;
    const personId = requirePerson();
    const previous = data;
    const prayer = data.prayers.find((item) => item.id === prayerId);
    if (!prayer) return;
    const prayed = !prayer.prayedByMe;
    setData({
      ...data,
      prayers: data.prayers.map((item) =>
        item.id === prayerId
          ? {
              ...item,
              prayedByMe: prayed,
              prayerCount: Math.max(0, item.prayerCount + (prayed ? 1 : -1)),
            }
          : item,
      ),
    });
    try {
      if (supabase && session)
        await api.setPrayerClick(
          supabase,
          data.organization.id,
          prayerId,
          personId,
          prayed,
        );
      notify(prayed ? "Your prayer was counted." : "Prayer removed.");
    } catch (cause) {
      setData(previous);
      throw cause;
    }
  };

  const markAnswered = async (prayerId: string, notes: string) => {
    if (!data) return;
    if (supabase && session) await api.answerPrayer(supabase, prayerId, notes);
    setData({
      ...data,
      prayers: data.prayers.map((item) =>
        item.id === prayerId
          ? { ...item, isAnswered: true, answeredNotes: notes }
          : item,
      ),
    });
    notify("Marked as answered.");
  };

  const saveMeeting = async (input: MeetingInput, id?: string) => {
    if (!data) return;
    if (supabase && session) {
      await api.saveMeeting(
        supabase,
        data.organization.id,
        data.currentUser.id,
        input.scope === "circle"
          ? data.groups.find((group) => group.id === input.groupId)?.leaderId
          : undefined,
        input,
        id,
      );
      if (input.scope === "circle" && input.groupId !== data.group?.id && input.groupId && session?.user) {
        const next = await api.loadAppData(supabase, session.user.id, input.groupId);
        next.currentUser.email = session.user.email ?? "";
        setData(next);
        setSelectedGroupId(next.group?.id);
      } else await refresh();
    } else {
      const { coverFile, removeCover, coverUrl, ...meetingFields } = input;
      const nextCoverUrl = coverFile
        ? URL.createObjectURL(coverFile)
        : removeCover
          ? undefined
          : coverUrl;
      if (id) {
        setData({
          ...data,
          meetings: data.meetings.map((meeting) =>
            meeting.id === id
              ? { ...meeting, ...meetingFields, coverUrl: nextCoverUrl }
              : meeting,
          ),
        });
      } else {
        setData({
          ...data,
          meetings: [
            ...data.meetings,
            {
              id: crypto.randomUUID(),
              createdBy: data.currentUser.id,
              status: "scheduled" as const,
              rsvps: {},
              ...meetingFields,
              coverUrl: nextCoverUrl,
            },
          ].sort((a, b) => a.meetingDate.localeCompare(b.meetingDate)),
        });
      }
    }
    notify(
      session
        ? id
          ? "Gathering updated."
          : "Gathering created."
        : id
          ? "Demo gathering updated for this session."
          : "Gathering added to this demo session only.",
    );
  };

  const cancelMeeting = async (id: string) => {
    if (!data) return;
    if (supabase && session) await api.cancelMeeting(supabase, id);
    setData({
      ...data,
      meetings: data.meetings.map((meeting) =>
        meeting.id === id ? { ...meeting, status: "cancelled" } : meeting,
      ),
      accessibleMeetings: data.accessibleMeetings?.map((meeting) =>
        meeting.id === id ? { ...meeting, status: "cancelled" } : meeting,
      ),
      dashboard: data.dashboard
        ? {
            ...data.dashboard,
            meetings: data.dashboard.meetings.map((meeting) =>
              meeting.id === id ? { ...meeting, status: "cancelled" } : meeting,
            ),
          }
        : undefined,
    });
    notify("Gathering cancelled.");
  };

  const requestMemberAccess = async (personId: string) => {
    if (!data?.group) return;
    if (supabase && session)
      await api.requestMemberAccess(supabase, data.group.id, personId);
    notify("Access request sent to an organization admin.");
  };

  const removeMember = async (membershipId: string) => {
    if (!data) return;
    if (supabase && session) await api.removeMember(supabase, membershipId);
    setData({
      ...data,
      members: data.members.filter(
        (member) => member.membershipId !== membershipId,
      ),
    });
    notify("Member removed.");
  };

  const openCheckin = async (meetingId: string) => {
    const code = supabase && session
      ? await api.openCheckin(supabase, meetingId)
      : Math.random().toString(36).slice(2, 8).toUpperCase();
    if (data)
      setData({
        ...data,
        meetings: data.meetings.map((meeting) =>
          meeting.id === meetingId
            ? { ...meeting, checkinCode: code }
            : meeting,
        ),
      });
    notify("Guest check-in is open.");
    return code;
  };

  const closeCheckin = async (meetingId: string) => {
    if (supabase && session) await api.closeCheckin(supabase, meetingId);
    if (data)
      setData({
        ...data,
        meetings: data.meetings.map((meeting) =>
          meeting.id === meetingId
            ? { ...meeting, checkinCode: undefined }
            : meeting,
        ),
      });
    notify("Guest check-in closed.");
  };

  const value = useMemo(
    () => ({
      data,
      session,
      loading,
      error,
      demoMode: !session,
      toast,
      refresh,
      signIn,
      signOut,
      selectGroup,
      createGroup,
      setRsvp,
      addPrayer,
      togglePrayer,
      markAnswered,
      saveMeeting,
      cancelMeeting,
      requestMemberAccess,
      removeMember,
      openCheckin,
      closeCheckin,
    }),
    [data, session, loading, error, toast, refresh],
  );

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
}

export function useCircles() {
  const context = useContext(AppContext);
  if (!context) throw new Error("useCircles must be used inside AppProvider");
  return context;
}
