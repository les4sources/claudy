# La palette ⌘K (redesign, Michael 2026-10-29) : un seul champ pour tout
# retrouver et agir. Répond un fragment HTML que `command-palette` (Stimulus)
# pose dans la palette à chaque frappe. Ouverte à tout compte : chaque groupe
# de résultats ne montre que ce que la personne peut lire.
class SearchesController < BaseController
  access_section :everyone

  def show
    @search = CommandPalette::Search.new(user: current_user, query: params[:q])
    render partial: "searches/results", locals: { search: @search }
  end

  private

  def set_presenters; end
end
