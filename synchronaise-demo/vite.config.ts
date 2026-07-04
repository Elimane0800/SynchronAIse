import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The preview server (port 4173) is what the SynchronAIse Action screenshots.
export default defineConfig({
  plugins: [react()],
  server: { port: 5174 },
  preview: { port: 4173 },
});
