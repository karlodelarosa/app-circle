import {
  ChevronLeft,
  ChevronRight,
  MapPin,
} from "lucide-react";
import {
  useEffect,
  useRef,
  useState,
  type FocusEvent,
  type PointerEvent,
} from "react";
import { Link } from "react-router-dom";
import type { Meeting } from "../types";
import { formatDate, formatTime } from "../lib/format";

interface DashboardJumbotronProps {
  defaultImage: string;
  gatherings: Meeting[];
  circleName?: string;
  circlePath?: string;
}

const AUTOPLAY_INTERVAL = 7000;
const SWIPE_THRESHOLD = 48;

const reducedMotionPreference = () =>
  window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;

export function DashboardJumbotron({
  defaultImage,
  gatherings,
  circleName = "your Circle",
  circlePath = "/circles",
}: DashboardJumbotronProps) {
  const slides = [
    { id: "welcome", meeting: undefined },
    ...gatherings.slice(0, 3).map((meeting) => ({
      id: meeting.id,
      meeting,
    })),
  ];
  const [activeIndex, setActiveIndex] = useState(0);
  const [hovered, setHovered] = useState(false);
  const [focusWithin, setFocusWithin] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [pageVisible, setPageVisible] = useState(!document.hidden);
  const [reducedMotion, setReducedMotion] = useState(reducedMotionPreference);
  const pointerStart = useRef<number | null>(null);
  const didDrag = useRef(false);

  const goTo = (index: number) => {
    setActiveIndex((index + slides.length) % slides.length);
  };

  useEffect(() => {
    setActiveIndex((index) => Math.min(index, slides.length - 1));
  }, [slides.length]);

  useEffect(() => {
    const media = window.matchMedia?.("(prefers-reduced-motion: reduce)");
    if (!media) return;
    const update = () => setReducedMotion(media.matches);
    media.addEventListener?.("change", update);
    return () => media.removeEventListener?.("change", update);
  }, []);

  useEffect(() => {
    const update = () => setPageVisible(!document.hidden);
    document.addEventListener("visibilitychange", update);
    return () => document.removeEventListener("visibilitychange", update);
  }, []);

  useEffect(() => {
    if (
      slides.length < 2 ||
      hovered ||
      focusWithin ||
      dragging ||
      reducedMotion ||
      !pageVisible
    ) return;
    const timer = window.setInterval(
      () => setActiveIndex((index) => (index + 1) % slides.length),
      AUTOPLAY_INTERVAL,
    );
    return () => window.clearInterval(timer);
  }, [slides.length, hovered, focusWithin, dragging, reducedMotion, pageVisible]);

  const startDrag = (event: PointerEvent<HTMLElement>) => {
    pointerStart.current = event.clientX;
    didDrag.current = false;
    setDragging(true);
    event.currentTarget.setPointerCapture?.(event.pointerId);
  };

  const moveDrag = (event: PointerEvent<HTMLElement>) => {
    if (pointerStart.current === null) return;
    if (Math.abs(event.clientX - pointerStart.current) > 8)
      didDrag.current = true;
  };

  const finishDrag = (event: PointerEvent<HTMLElement>) => {
    if (pointerStart.current === null) return;
    const distance = event.clientX - pointerStart.current;
    if (Math.abs(distance) >= SWIPE_THRESHOLD)
      goTo(activeIndex + (distance < 0 ? 1 : -1));
    pointerStart.current = null;
    setDragging(false);
    event.currentTarget.releasePointerCapture?.(event.pointerId);
  };

  const handleBlur = (event: FocusEvent<HTMLElement>) => {
    if (!event.currentTarget.contains(event.relatedTarget)) setFocusWithin(false);
  };

  return (
    <section
      aria-label="Community highlights"
      aria-roledescription="carousel"
      className="relative overflow-hidden rounded-[2rem] bg-ink text-paper"
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onFocus={() => setFocusWithin(true)}
      onBlur={handleBlur}
      onKeyDown={(event) => {
        if (event.key === "ArrowLeft") {
          event.preventDefault();
          goTo(activeIndex - 1);
        }
        if (event.key === "ArrowRight") {
          event.preventDefault();
          goTo(activeIndex + 1);
        }
      }}
    >
      <div
        className={`flex touch-pan-y select-none ${reducedMotion ? "" : "transition-transform duration-500 ease-out"}`}
        style={{ transform: `translateX(-${activeIndex * 100}%)` }}
        onPointerDown={startDrag}
        onPointerMove={moveDrag}
        onPointerUp={finishDrag}
        onPointerCancel={(event) => {
          pointerStart.current = null;
          setDragging(false);
          event.currentTarget.releasePointerCapture?.(event.pointerId);
        }}
        onClickCapture={(event) => {
          if (didDrag.current) {
            event.preventDefault();
            event.stopPropagation();
            didDrag.current = false;
          }
        }}
      >
        {slides.map((slide, index) => {
          const meeting = slide.meeting;
          const isActive = index === activeIndex;
          if (!meeting)
            return (
              <div
                key={slide.id}
                aria-hidden={!isActive}
                aria-label={`Slide ${index + 1} of ${slides.length}`}
                aria-roledescription="slide"
                className="relative flex min-h-[24rem] w-full shrink-0 sm:min-h-[30rem]"
                role="group"
              >
                <img
                  src={defaultImage}
                  alt=""
                  className="absolute inset-0 h-full w-full object-cover"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-black/90 via-black/35 to-transparent" />
                <div className={`relative mt-auto max-w-4xl p-6 sm:p-10 ${slides.length > 1 ? "pb-24 sm:pb-24" : "pb-9 sm:pb-11"}`}>
                  <p className="text-sm text-paper/80">Welcome to {circleName}</p>
                  <h2 className="mt-2 max-w-3xl font-display text-4xl leading-[1.04] sm:text-6xl">
                    Make room for one another.
                  </h2>
                  <p className="mt-3 max-w-xl text-sm leading-6 text-paper/80 sm:text-base">
                    Your Circle’s gatherings, prayers, and shared life begin here.
                  </p>
                  <Link
                    to={circlePath}
                    className="secondary-button mt-6"
                    tabIndex={isActive ? 0 : -1}
                  >
                    View my Circle
                  </Link>
                </div>
              </div>
            );
          return (
            <Link
              key={slide.id}
              to={`/gatherings/${meeting.id}`}
              aria-hidden={!isActive}
              aria-label={`Slide ${index + 1} of ${slides.length}: ${meeting.title}`}
              aria-roledescription="slide"
              className="group relative flex min-h-[22rem] w-full shrink-0 sm:min-h-[28rem]"
              tabIndex={isActive ? 0 : -1}
            >
              <img
                src={meeting.coverUrl || defaultImage}
                alt=""
                className="absolute inset-0 h-full w-full object-cover"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-ink/95 via-ink/35 to-ink/5" />
              <div className="relative mt-auto max-w-4xl p-6 pb-24 sm:p-10 sm:pb-24">
                <p className="text-sm text-paper/75">
                  Upcoming gathering · {formatDate(meeting.meetingDate)} at {formatTime(meeting.meetingDate)}
                </p>
                <h2 className="mt-3 font-display text-4xl leading-tight sm:text-6xl">
                  {meeting.title}
                </h2>
                <p className="mt-3 flex items-center gap-2 text-sm text-paper/80">
                  <MapPin size={15} /> {meeting.location}
                </p>
                <span className="mt-6 inline-flex items-center gap-2 text-sm font-medium">
                  View gathering <ChevronRight size={16} />
                </span>
              </div>
            </Link>
          );
        })}
      </div>

      {slides.length > 1 && (
        <div className="absolute inset-x-4 bottom-4 z-10 flex items-center justify-between gap-3 sm:inset-x-6 sm:bottom-6">
          <div className="flex items-center gap-1 rounded-full border border-paper/20 bg-ink/35 p-1 backdrop-blur-md">
            <button
              type="button"
              className="grid h-11 w-11 place-items-center rounded-full text-paper hover:bg-paper/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-paper"
              onClick={() => goTo(activeIndex - 1)}
              aria-label="Previous slide"
            >
              <ChevronLeft size={19} />
            </button>
            <button
              type="button"
              className="grid h-11 w-11 place-items-center rounded-full text-paper hover:bg-paper/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-paper"
              onClick={() => goTo(activeIndex + 1)}
              aria-label="Next slide"
            >
              <ChevronRight size={19} />
            </button>
          </div>
          <div className="flex min-h-11 items-center gap-1.5 rounded-full border border-paper/20 bg-ink/35 px-3 backdrop-blur-md">
            {slides.map((slide, index) => (
              <button
                key={slide.id}
                type="button"
                aria-label={`Show slide ${index + 1}`}
                aria-current={index === activeIndex ? "true" : undefined}
                className={`h-2.5 rounded-full transition-[width,background-color] motion-reduce:transition-none ${
                  index === activeIndex ? "w-7 bg-paper" : "w-2.5 bg-paper/45 hover:bg-paper/75"
                }`}
                onClick={() => goTo(index)}
              />
            ))}
          </div>
        </div>
      )}
    </section>
  );
}
