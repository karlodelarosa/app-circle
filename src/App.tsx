import { Navigate, Route, Routes } from "react-router-dom";
import { useCircles } from "./AppContext";
import { AppShell } from "./components/AppShell";
import { CirclePage } from "./pages/CirclePage";
import { ContentPage } from "./pages/ContentPage";
import { ConnectionsPage } from "./pages/ConnectionsPage";
import { GatheringDetailPage } from "./pages/GatheringDetailPage";
import { GatheringsPage } from "./pages/GatheringsPage";
import { HomePage } from "./pages/HomePage";
import { SignInPage } from "./pages/SignInPage";
import {
  GalleriesPage,
  GalleryPage,
  PublicCirclePage,
  PublicCirclesPage,
  PublicGatheringPage,
  PublicGatheringsPage,
  PublicHomePage,
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
  if (loading) return <LoadingScreen />;
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

export default function App() {
  return (
    <Routes>
      <Route path="/sign-in" element={<RootEntry />} />
      <Route element={<ProtectedApp />}>
        <Route path="/" element={<HomePage />} />
        <Route path="/circles" element={<CirclePage />} />
        <Route path="/circles/:circleId" element={<CirclePage />} />
        <Route path="/gatherings" element={<GatheringsPage />} />
        <Route path="/gatherings/new" element={<GatheringsPage />} />
        <Route path="/gatherings/:id" element={<GatheringDetailPage />} />
        <Route path="/gatherings/:id/:mode" element={<GatheringDetailPage />} />
        <Route path="/people" element={<Navigate to="/circles" replace />} />
        <Route path="/content" element={<ContentPage />} />
        <Route path="/connections" element={<ConnectionsPage />} />
        <Route path="/connections/:connectionId" element={<ConnectionsPage />} />
      </Route>
      <Route path="/app/*" element={<Navigate to="/" replace />} />
      <Route path="/:orgSlug" element={<PublicShell />}>
        <Route index element={<PublicHomePage />} />
        <Route path="gatherings" element={<PublicGatheringsPage />} />
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
  );
}
