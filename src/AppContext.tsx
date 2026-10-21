import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import type { Session } from "@supabase/supabase-js";
import { demoData } from "./data/demo";
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

export function AppProvider({ children }: { children: ReactNode }) {
  const [data, setData] = useState<AppData | null>(
    isSupabaseConfigured ? null : structuredClone(demoData),
  );
  const [session, setSession] = useState<Session | null>(null);
  const [selectedGroupId, setSelectedGroupId] = useState<string>();
  const [loading, setLoading] = useState(isSupabaseConfigured);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  const notify = useCallback((message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(null), 2800);
  }, []);

  const refresh = useCallback(async () => {
    if (!supabase || !session?.user) return;
    setLoading(true);
    setError(null);
    try {
      const next = await api.loadAppData(
        supabase,
        session.user.id,
        selectedGroupId,
      );
      next.currentUser.email = session.user.email ?? "";
      setData(next);
      setSelectedGroupId(next.group?.id);
    } catch (cause) {
      setData(null);
      setError(
        !navigator.onLine
          ? "You’re offline. The Circles shell is available, but private group data needs a connection. Reconnect and try again."
          : getErrorMessage(cause, "Circles could not load your group."),
      );
    } finally {
      setLoading(false);
    }
  }, [session, selectedGroupId]);

  useEffect(() => {
    if (!supabase) return;
    supabase.auth.getSession().then(({ data: result }) => {
      setSession(result.session);
      if (!result.session) setLoading(false);
    });
    const { data: listener } = supabase.auth.onAuthStateChange(
      (_event, nextSession) => {
        setSession(nextSession);
        if (!nextSession) {
          setData(null);
          setLoading(false);
        }
      },
    );
    return () => listener.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (session) void refresh();
  }, [session, refresh]);

  const requirePerson = () => {
    const personId = data?.currentUser.personId;
    if (!personId)
      throw new Error(
        "Your administrator account is not linked to a directory person. Link it before participating as a member.",
      );
    return personId;
  };

  const signIn = async (email: string, password: string) => {
    if (!supabase) return;
    const { error: authError } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (authError) throw authError;
    notify("Signed in.");
  };

  const signOut = async () => {
    if (supabase) await supabase.auth.signOut({ scope: "local" });
  };

  const selectGroup = async (groupId: string) => {
    setSelectedGroupId(groupId);
    if (!supabase && data) {
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
    if (supabase) {
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
    });
    try {
      if (supabase)
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
    if (!data?.group) return;
    const personId = requirePerson();
    if (supabase) {
      await api.createPrayer(
        supabase,
        data.organization.id,
        data.group.id,
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
            groupId: data.group.id,
            userId: personId,
            authorName: data.currentUser.fullName,
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
    notify("Prayer shared with your circle.");
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
      if (supabase)
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
    if (supabase) await api.answerPrayer(supabase, prayerId, notes);
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
    if (!data?.group) return;
    if (supabase) {
      await api.saveMeeting(
        supabase,
        data.organization.id,
        data.group.id,
        data.currentUser.id,
        data.group.leaderId,
        input,
        id,
      );
      await refresh();
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
              groupId: data.group.id,
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
    notify(id ? "Gathering updated." : "Gathering created.");
  };

  const cancelMeeting = async (id: string) => {
    if (!data) return;
    if (supabase) await api.cancelMeeting(supabase, id);
    setData({
      ...data,
      meetings: data.meetings.map((meeting) =>
        meeting.id === id ? { ...meeting, status: "cancelled" } : meeting,
      ),
    });
    notify("Gathering cancelled.");
  };

  const requestMemberAccess = async (personId: string) => {
    if (!data?.group) return;
    if (supabase)
      await api.requestMemberAccess(supabase, data.group.id, personId);
    notify("Access request sent to an organization admin.");
  };

  const removeMember = async (membershipId: string) => {
    if (!data) return;
    if (supabase) await api.removeMember(supabase, membershipId);
    setData({
      ...data,
      members: data.members.filter(
        (member) => member.membershipId !== membershipId,
      ),
    });
    notify("Member removed.");
  };

  const openCheckin = async (meetingId: string) => {
    const code = supabase
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
    if (supabase) await api.closeCheckin(supabase, meetingId);
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
      demoMode: !isSupabaseConfigured,
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
