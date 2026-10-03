# Reporting › Site web : les statistiques de visites de www.les4sources.be,
# mesurées sans cookie (2026-10-03). Visible par tout membre connecté — la
# garde vient de BaseController (connexion, membre actif, comptes restreints
# renvoyés vers leur planning).
class SiteStatsController < BaseController
  breadcrumb "Reporting", :reports_path, match: :exact
  breadcrumb "Site web", :site_stats_path, match: :force

  def show
    SiteVisitSalt.purge_before!(Time.zone.today)
    @report = SiteStats::Report.new(period: params[:period])
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "reports")
    @reports_view = true
    @home_view = true
  end
end
