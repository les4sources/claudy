# Flux iCal des gardes, abonnable depuis Google Agenda (issue #142).
#
# Hérite de `ActionController::Base` et NON de `BaseController` : Google Agenda
# récupère l'URL anonymement, sans cookie ni session Devise. Un `authenticate_user!`
# rendrait le flux inabonnable.
#
# Le seul garde-fou est donc le jeton `?token=` :
#   - comparé en temps constant à `ENV["WATCHMAN_ICS_TOKEN"]` ;
#   - absent, faux, ou variable d'environnement non configurée → **404**, jamais
#     401/403 : on ne confirme même pas l'existence du flux.
class WatchmanIcsController < ActionController::Base
  layout false

  def show
    return head :not_found unless authorized?

    render plain: Watchmen::IcalFeed.new.to_ics, content_type: "text/calendar"
  end

  private

  def authorized?
    expected = ENV["WATCHMAN_ICS_TOKEN"].to_s
    provided = params[:token].to_s
    # Pas de jeton configuré → le flux n'est PAS ouvert par défaut.
    return false if expected.blank? || provided.blank?

    ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end
end
