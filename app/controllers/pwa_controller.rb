# Le manifeste de l'application installable (redesign, Michael 2026-10-29,
# maquette « Claudy dans la poche »). Hors de `BaseController` : le navigateur
# le lit sans session, avant même la connexion. Généré plutôt que statique
# pour que les raccourcis suivent les routes.
class PwaController < ActionController::Base
  THEME_COLOR = "#224246".freeze
  BACKGROUND_COLOR = "#faf6f0".freeze

  def manifest
    expires_in 1.hour, public: true
    render json: {
      name: "Claudy · Les 4 Sources",
      short_name: "Claudy",
      description: "L'app des 4 Sources : séjours, agenda, cuisine et comptabilité du domaine d'Ahinvaux.",
      lang: "fr",
      id: "/",
      start_url: "/?source=pwa",
      scope: "/",
      display: "standalone",
      orientation: "portrait",
      theme_color: THEME_COLOR,
      background_color: BACKGROUND_COLOR,
      icons: [
        { src: "/icons/claudy-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
        { src: "/icons/claudy-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
        { src: "/icons/claudy-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" }
      ],
      # L'appui long sur l'icône : les trois gestes les plus fréquents.
      shortcuts: [
        shortcut("Nouveau séjour", new_stay_path),
        shortcut("Agenda du jour", today_path),
        shortcut("Compter la caisse", new_finance_cash_count_path)
      ]
    }, content_type: "application/manifest+json"
  end

  private

  def shortcut(name, path)
    { name: name, short_name: name, url: "#{path}?source=pwa",
      icons: [{ src: "/icons/claudy-96.png", sizes: "96x96", type: "image/png" }] }
  end
end
