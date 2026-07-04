import { StatusCard } from "../components/StatusCard";

// Fixed props so CI snapshots are deterministic across runs.
export function StatusCardEntry() {
  return (
    <StatusCard
      variant="danger"
      title="Payment failed"
      description="Your last transaction could not be processed."
      actionLabel="Retry payment"
    />
  );
}
