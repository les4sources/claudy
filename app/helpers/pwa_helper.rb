# Claudy installable (redesign, Michael 2026-10-29). Le service worker ne
# s'enregistre qu'en production, ou en local avec `PWA_SERVICE_WORKER=1` : en
# développement il garderait en cache des fichiers que Vite reconstruit, et les
# specs n'ont rien à en faire.
module PwaHelper
  def pwa_service_worker?
    Rails.env.production? || ENV["PWA_SERVICE_WORKER"] == "1"
  end
end
