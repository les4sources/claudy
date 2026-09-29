module Api
  module V1
    # Les reconstructions du site les4sources.be (voir `WebsiteRebuildJob`).
    #
    # GET : les dernières demandes et leur issue — ce qui permet de voir, sans
    # accès aux logs, si une publication a bien relancé le site. `meta` dit si
    # le webhook est configuré (jamais son URL).
    # POST : demande une reconstruction tout de suite, sans fenêtre de
    # regroupement (réponse 202, la demande est traitée en arrière-plan).
    class WebsiteRebuildsController < BaseController
      def index
        @website_rebuilds = WebsiteRebuild.recent.limit(20)
      end

      def create
        WebsiteRebuildJob.request!(trigger: "api", immediate: true)
        @website_rebuild = WebsiteRebuild.recent.first
        render :show, status: :accepted
      end
    end
  end
end
