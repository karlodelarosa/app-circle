import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, ".", "");
  const supabaseUrl = mode === "e2e" ? "" : env.VITE_SUPABASE_URL || "";
  const supabaseKey = mode === "e2e" ? "" : env.VITE_SUPABASE_PUBLISHABLE_OR_ANON_KEY || "";

  return {
    define: {
      "import.meta.env.VITE_SUPABASE_URL": JSON.stringify(supabaseUrl),
      "import.meta.env.VITE_SUPABASE_PUBLISHABLE_OR_ANON_KEY":
        JSON.stringify(supabaseKey),
    },
    plugins: [
      react(),
      VitePWA({
        registerType: "prompt",
        includeAssets: [
          "assets/devotional-table.webp",
          "assets/welcome-table.webp",
          "assets/gathering-placeholder-1.webp",
          "assets/gathering-placeholder-2.webp",
          "circles-icon-192.png",
          "circles-icon-512.png",
        ],
        manifest: {
          name: "Circles — Cell Group",
          short_name: "Circles",
          description: "Gather, pray, and grow together.",
          theme_color: "#596047",
          background_color: "#F3EFE5",
          display: "standalone",
          start_url: "/?source=pwa",
          icons: [
            {
              src: "/circles-icon-192.png?v=2",
              sizes: "192x192",
              type: "image/png",
            },
            {
              src: "/circles-icon-512.png?v=2",
              sizes: "512x512",
              type: "image/png",
            },
          ],
        },
        workbox: {
          navigateFallback: "/index.html",
          globPatterns: ["**/*.{js,css,html,svg,png,webp,woff2}"],
        },
      }),
    ],
    build: {
      rollupOptions: {
        output: {
          manualChunks(id) {
            if (!id.includes("node_modules")) return;
            if (id.includes("@supabase")) return "supabase";
            if (id.includes("react") || id.includes("scheduler")) return "react";
            if (id.includes("qrcode")) return "qrcode";
            if (id.includes("lucide-react")) return "icons";
            return "vendor";
          },
        },
      },
    },
  };
});
