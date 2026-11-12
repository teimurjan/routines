const RADIUS = 5.1;
const LENGTH = 2 * Math.PI * RADIUS;

// The tint follows the Swift view: faint below 1%, warning below 60%, success after.
export const progressTone = (value: number) => (value < 0.01 ? "faint" : value < 0.6 ? "warning" : "success");

export const ProgressRing = ({ value }: { value: number }) => {
  const shown = Math.max(0.02, Math.min(1, value));
  return (
    <svg class="rt-ring" data-tone={progressTone(value)} viewBox="0 0 12 12" role="img" aria-label={`${Math.round(value * 100)}%`}>
      <circle class="rt-ring__track" cx="6" cy="6" r={RADIUS} />
      <circle class="rt-ring__value" cx="6" cy="6" r={RADIUS} stroke-dasharray={`${shown * LENGTH} ${LENGTH}`} />
    </svg>
  );
};
