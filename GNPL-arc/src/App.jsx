import { useState } from "react";
import ArchDiagram from "../architecture_diagram.jsx";
import PipelineArch from "../pipeline_architecture.jsx";
import SaveToStorage from "../save_to_storage.jsx";

const TABS = [
  { key: "arch",     label: "System Architecture",  Component: ArchDiagram   },
  { key: "pipeline", label: "Pipeline Topology",    Component: PipelineArch  },
  { key: "storage",  label: "Storage Snapshot",     Component: SaveToStorage },
];

export default function App() {
  const [active, setActive] = useState("arch");
  const { Component } = TABS.find(t => t.key === active);

  return (
    <div style={{ fontFamily: "'Inter', sans-serif" }}>
      {/* Nav bar */}
      <div style={{
        display: "flex", gap: 4, padding: "8px 16px",
        background: "#060d1a",
        borderBottom: "1px solid rgba(255,255,255,0.07)",
        position: "sticky", top: 0, zIndex: 100,
      }}>
        {TABS.map(({ key, label }) => (
          <button
            key={key}
            onClick={() => setActive(key)}
            style={{
              padding: "6px 16px",
              borderRadius: 6,
              border: "none",
              cursor: "pointer",
              fontFamily: "'Fira Code', monospace",
              fontSize: 11,
              fontWeight: 700,
              letterSpacing: 0.5,
              background: active === key ? "#f59e0b" : "rgba(255,255,255,0.05)",
              color: active === key ? "#0f172a" : "rgba(255,255,255,0.45)",
              transition: "all 0.2s",
            }}
          >
            {label}
          </button>
        ))}
      </div>

      {/* Active view */}
      <Component />
    </div>
  );
}
