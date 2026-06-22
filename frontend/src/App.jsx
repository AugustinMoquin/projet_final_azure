import { useEffect, useState } from "react";
import * as signalR from "@microsoft/signalr";
import { FUNCTION_BASE_URL, fetchDocuments } from "./api.js";

const STATUS_ORDER = ["UPLOADED", "QUEUED", "PROCESSING", "PROCESSED", "ERROR"];

function statusClass(status) {
  if (status === "ERROR") return "badge error";
  if (status === "PROCESSED") return "badge done";
  return "badge pending";
}

export default function App() {
  // documentId -> document record
  const [docs, setDocs] = useState({});
  const [connection, setConnection] = useState("connecting");

  function applyUpdate(doc) {
    if (!doc || !doc.documentId) return;
    setDocs((prev) => ({ ...prev, [doc.documentId]: { ...prev[doc.documentId], ...doc } }));
  }

  useEffect(() => {
    // Initial state from Cosmos.
    fetchDocuments()
      .then((list) => {
        const map = {};
        for (const d of list) map[d.documentId] = d;
        setDocs(map);
      })
      .catch(() => {/* API may be cold; SignalR updates will fill in */});

    // Real-time updates via SignalR. The client appends /negotiate to this URL.
    const conn = new signalR.HubConnectionBuilder()
      .withUrl(FUNCTION_BASE_URL)
      .withAutomaticReconnect()
      .configureLogging(signalR.LogLevel.Warning)
      .build();

    conn.on("statusUpdate", applyUpdate);
    conn.onreconnecting(() => setConnection("reconnecting"));
    conn.onreconnected(() => setConnection("connected"));
    conn.onclose(() => setConnection("disconnected"));

    conn
      .start()
      .then(() => setConnection("connected"))
      .catch(() => setConnection("disconnected"));

    return () => conn.stop();
  }, []);

  const rows = Object.values(docs).sort((a, b) =>
    (a.name || "").localeCompare(b.name || ""),
  );

  return (
    <main className="app">
      <header>
        <h1>Document Pipeline</h1>
        <span className={`conn ${connection}`}>SignalR: {connection}</span>
      </header>

      {rows.length === 0 ? (
        <p className="empty">No documents yet. Upload a file to the <code>documents</code> container.</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th>Document</th>
              <th>Status</th>
              <th>Tags</th>
              <th>Tagged by</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((d) => (
              <tr key={d.documentId}>
                <td>{d.name}</td>
                <td>
                  <span className={statusClass(d.status)}>{d.status}</span>
                  {d.error && <div className="errmsg">{d.error}</div>}
                </td>
                <td>{(d.tags || []).join(", ")}</td>
                <td>{d.taggedBy || "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <footer>
        <small>Pipeline stages: {STATUS_ORDER.join(" → ")}</small>
      </footer>
    </main>
  );
}
