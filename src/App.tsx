import { Navigate, Route, Routes, useLocation } from "react-router-dom";
import type { ReactNode } from "react";
import { useCircles } from "./AppContext";
import { AppShell } from "./components/AppShell";
import { CirclePage } from "./pages/CirclePage";
import { ContentPage } from "./pages/ContentPage";
import { ConnectionsPage } from "./pages/ConnectionsPage";
import { GatheringDetailPage } from "./pages/GatheringDetailPage";
import { GatheringsPage } from "./pages/GatheringsPage";
import { HomePage } from "./pages/HomePage";
import { SignInPage } from "./pages/SignInPage";
import { PrayerPage } from "./pages/PrayerPage";
import { MemberTestimonyPage } from "./pages/MemberTestimonyPage";
import { ChangePasswordPage } from "./pages/ChangePasswordPage";
import { MorePage } from "./pages/MorePage";
import { PwaUpdatePrompt, RouteScrollManager } from "./components/RouteExperience";
import {
  GalleriesPage,
  GalleryPage,
  PublicCirclePage,
  PublicCirclesPage,
  PublicGatheringPage,
  PublicGatheringsPage,
  PublicHomePage,
  PublicUpdatesPage,
  PublicShell,
  TestimoniesPage,
  TestimonyPage,
} from "./pages/PublicPages";

function LoadingScreen() {
  return (
    <div className="grid min-h-screen place-items-center bg-parchment">
      <div className="h-9 w-9 animate-spin rounded-full border-2 border-line border-t-olive" />
    </div>
  );
}
function ErrorScreen({
  message,
  retry,
  signInAgain,
}: {
  message: string;
  retry: () => void;
  signInAgain?: () => void;
}) {
  return (
    <div className="grid min-h-screen place-items-center bg-parchment p-6">
      <div className="max-w-md text-center">
        <h1 className="font-display text-4xl">Circles could not open.</h1>
        <p className="mt-3 leading-6 text-muted">{message}</p>
        <div className="mt-6 flex justify-center gap-3">
          <button onClick={retry} className="primary-button">
            Try again
          </button>
          {signInAgain && (
            <button onClick={signInAgain} className="secondary-button">
              Sign in again
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
function RootEntry() {
  const { session, loading } = useCircles();
  if (loading) return <LoadingScreen />;
  if (session) return <Navigate to="/" replace />;
  return <SignInPage />;
}
function ProtectedApp() {
  const { data, session, loading, error, refresh, signOut } = useCircles();
  const location = useLocation();
  if (loading) return <LoadingScreen />;
  if (!session) {
    const next = `${location.pathname}${location.search}`;
    return (
      <Navigate
        to={`/sign-in?next=${encodeURIComponent(next)}`}
        replace
      />
    );
  }
  if (data?.account.mustChangePassword && location.pathname !== "/change-password")
    return <Navigate to="/change-password" replace />;
  if (error && !data)
    return (
      <ErrorScreen
        message={error}
        retry={() => void refresh()}
        signInAgain={() => void signOut()}
      />
    );
  if (!data) return <LoadingScreen />;
  return <AppShell />;
}
function HomeEntry() {
  const { data } = useCircles();
  if (!data) return null;
  if (data.currentUser.role === "member")
    return <Navigate to={data.group ? `/circles/${data.group.id}` : "/circles"} replace />;
  return <HomePage />;
}
function LeaderOnly({ children }: { children: ReactNode }) {
  const { data } = useCircles();
  if (!data) return null;
  const canLead = data.currentUser.role === "admin" || data.groups.some((group) => group.role === "leader");
  return canLead ? children : <Navigate to="/circles" replace />;
}

export default function App() {
  return (
    <>
      <RouteScrollManager />
      <PwaUpdatePrompt />
      <Routes>
      <Route path="/sign-in" element={<RootEntry />} />
      <Route element={<ProtectedApp />}>
        <Route path="/" element={<HomeEntry />} />
        <Route path="/circles" element={<CirclePage />} />
        <Route path="/circles/:circleId" element={<CirclePage />} />
        <Route path="/gatherings" element={<GatheringsPage />} />
        <Route path="/gatherings/new" element={<GatheringsPage />} />
        <Route path="/gatherings/:id" element={<GatheringDetailPage />} />
        <Route path="/gatherings/:id/:mode" element={<GatheringDetailPage />} />
        <Route path="/people" element={<Navigate to="/circles" replace />} />
        <Route path="/prayer" element={<PrayerPage />} />
        <Route path="/share-testimony" element={<MemberTestimonyPage />} />
        <Route path="/change-password" element={<ChangePasswordPage />} />
        <Route path="/more" element={<LeaderOnly><MorePage /></LeaderOnly>} />
        <Route path="/content" element={<LeaderOnly><ContentPage /></LeaderOnly>} />
        <Route path="/connections" element={<LeaderOnly><ConnectionsPage /></LeaderOnly>} />
        <Route path="/connections/:connectionId" element={<LeaderOnly><ConnectionsPage /></LeaderOnly>} />
      </Route>
      <Route path="/app/*" element={<Navigate to="/" replace />} />
      <Route path="/:orgSlug" element={<PublicShell />}>
        <Route index element={<PublicHomePage />} />
        <Route path="gatherings" element={<PublicGatheringsPage />} />
        <Route path="updates" element={<PublicUpdatesPage />} />
        <Route
          path="gatherings/:gatheringSlug"
          element={<PublicGatheringPage />}
        />
        <Route path="testimonies" element={<TestimoniesPage />} />
        <Route path="testimonies/:testimonySlug" element={<TestimonyPage />} />
        <Route path="galleries" element={<GalleriesPage />} />
        <Route path="galleries/:gallerySlug" element={<GalleryPage />} />
        <Route path="circles" element={<PublicCirclesPage />} />
        <Route path="circles/:circleSlug" element={<PublicCirclePage />} />
      </Route>
      </Routes>
    </>
  );
}
