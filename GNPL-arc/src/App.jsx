import { useState } from "react";
import ArchDiagram from "../architecture_diagram.jsx";
import PipelineArch from "../pipeline_architecture.jsx";
import SaveToStorage from "../save_to_storage.jsx";

const TABS = [
  { key: "arch",     label: "System Architecture", Component: ArchDiagram   },
  { key: "pipeline", label: "Pipeline Topology",   Component: PipelineArch  },
  { key: "storage",  label: "Storage Snapshot",    Component: SaveToStorage },
];

export default function App() {
  const [active, setActive] = useState("arch");
  const { Component } = TABS.find(t => t.key === active);

  return (
    <div style={{ fontFamily: "'Inter', sans-serif", background: "#f1f5f9", minHeight: "100vh" }}>
      {/* Nav bar */}
      <div style={{
        display: "flex", gap: 4, padding: "10px 20px",
        background: "#fff",
        borderBottom: "1px solid #e2e8f0",
        position: "sticky", top: 0, zIndex: 100,
        boxShadow: "0 1px 3px rgba(0,0,0,0.06)",
      }}>
        <div style={{ display: "flex", alignItems: "center", marginRight: 16, gap: 8 }}>
          <div style={{ width: 3, height: 20, background: "#b45309", borderRadius: 2 }} />
          <span style={{ fontFamily: "'Fira Code', monospace", fontSize: 11, fontWeight: 700, color: "#b45309", letterSpacing: 1 }}>
            GNPL-ARC
          </span>
        </div>
        {TABS.map(({ key, label }) => (
          <button key={key} onClick={() => setActive(key)} style={{
            padding: "6px 16px", borderRadius: 6,
            border: active === key ? "1.5px solid #b45309" : "1.5px solid #e2e8f0",
            cursor: "pointer",
            fontFamily: "'Fira Code', monospace", fontSize: 11, fontWeight: 700,
            background: active === key ? "#b45309" : "#f8fafc",
            color: active === key ? "#fff" : "#475569",
            transition: "all 0.2s",
          }}>
            {label}
          </button>
        ))}
      </div>

      <Component />
    </div>
  );
}
