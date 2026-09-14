# Le centre de notifications (epic #242, phase 2).
#
# `show` est le point d'entrée de TOUS les liens — la cloche, la page, l'email :
# il marque la notification lue, puis redirige vers l'objet. Une seule mécanique
# « lu + atterrissage », jamais recopiée ailleurs.
#
# Un utilisateur ne voit QUE ses notifications : toutes les lectures partent de
# `current_user.notifications`, jamais de `Notification.find`.
class NotificationsController < BaseController
  PER_PAGE = 30
  # Le menu déroulant de la cloche en montre dix — au-delà, « Tout voir ».
  MENU_SIZE = 10

  breadcrumb "Notifications", :notifications_path, match: :exact

  def index
    @notifications = scope.newest_first.paginate(page: params[:page], per_page: PER_PAGE)
    @unread_count  = scope.unread.count
  end

  # Le fragment de la cloche, rechargé par son Turbo Frame à chaque navigation.
  # Rendu sans layout : il ne vaut que par son contenu.
  def bell
    @unread_count  = scope.unread.count
    @notifications = scope.newest_first.limit(MENU_SIZE)

    render :bell, layout: false
  end

  def show
    notification = scope.find(params[:id])
    notification.mark_read!

    redirect_to safe_target(notification), allow_other_host: false
  end

  def read_all
    scope.unread.update_all(read_at: Time.current)

    redirect_back fallback_location: notifications_path, notice: "Tout est marqué comme lu."
  end

  # « Recevoir aussi par email » — la seule préférence de cet epic.
  def preferences
    current_user.update(notify_by_email: ActiveModel::Type::Boolean.new.cast(params.dig(:user, :notify_by_email)))

    redirect_to notifications_path, notice: preferences_notice
  end

  private

  def scope = current_user.notifications

  # L'`url` d'une notification est posée par l'application elle-même, mais elle
  # est stockée : on ne renvoie donc jamais ailleurs que chez nous. Un chemin
  # qui ne commence pas par « / » retombe sur l'accueil.
  def safe_target(notification)
    url = notification.url.to_s
    url.start_with?("/") && !url.start_with?("//") ? url : root_path
  end

  def preferences_notice
    if current_user.notify_by_email?
      "Vous recevrez aussi vos notifications par email."
    else
      "Vos notifications resteront dans Claudy, sans email."
    end
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new
  end
end
