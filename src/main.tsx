import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import { applyVisitorChatSessionHeader } from "./lib/visitor-chat-session";

// Bind visitor chat session header so RLS on chat_conversations/chat_messages
// only returns rows belonging to this browser.
applyVisitorChatSessionHeader();

const root = document.getElementById("root");

if (!root) {
  throw new Error("FlowWink root element was not found");
}

createRoot(root).render(<App />);
