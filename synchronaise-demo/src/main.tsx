import ReactDOM from "react-dom/client";
import { StatusCardEntry } from "./render/status-card-entry";

// CI render harness: the SynchronAIse Action navigates to /?component=<name>
// and screenshots the [data-node='card'] element. Register render targets here.
const REGISTRY: Record<string, () => JSX.Element> = {
  StatusCard: StatusCardEntry,
};

function mount() {
  const name = new URLSearchParams(window.location.search).get("component") || "StatusCard";
  const Entry = REGISTRY[name] || StatusCardEntry;
  ReactDOM.createRoot(document.getElementById("root")!).render(
    <div style={{ padding: 40, display: "inline-block" }}>
      <Entry />
    </div>
  );
}

mount();
