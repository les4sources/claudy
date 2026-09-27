# Les fils de commentaires de la carte (epic #348, phase 11).
#
# Création ATOMIQUE : en mode Commentaires, toucher la carte ouvre la fiche
# d'un point qui n'existe pas encore (`new`, lat/lng dans l'URL). Le point et
# son premier message ne sont créés qu'ensemble, à la publication (`create`) :
# annuler ou fermer la fiche ne laisse aucun point orphelin, puisqu'il n'y a
# rien à supprimer.
#
# Chaque geste répond par un Turbo Stream sur la fiche (`feature_panel`) :
# - une réponse est AJOUTÉE au fil, le formulaire revient vide ;
# - résoudre, rouvrir, publier le premier message remplacent la fiche, marquée
#   `data-feature-saved` pour que la carte recharge la bulle du point ;
# - supprimer la racine efface le point (même marqueur que `MapFeaturesController`).
#
# On ne supprime que SES messages (403 sinon). Un message inconnu ou déjà
# supprimé n'existe pas (404).
class MapCommentsController < BaseController
  PANEL_FRAME = MapFeaturesController::PANEL_FRAME

  before_action :get_comment, only: %i[reply resolve reopen destroy]

  # GET /map/comments/new?lat=…&lng=… — la fiche d'un point pas encore créé.
  def new
    @lat, @lng = coordinates
    render :new, layout: false
  end

  # POST /map/comments — lat, lng, map_comment[body].
  def create
    lat, lng = coordinates
    feature = MapLayer.for_kind(:comments).map_features.new(
      feature_kind: "comment", created_by: current_user,
      geometry: { "type" => "Point", "coordinates" => [lng, lat] }
    )
    comment = feature.map_comments.build(author: current_user, body: body_param)

    # `has_many` enregistre le message neuf avec le point, dans la même
    # transaction : l'un ne peut pas exister sans l'autre.
    if comment.valid? && feature.save
      respond_panel(feature, saved: true)
    else
      error = comment.errors[:body].any? ? "Écrivez un premier message." : "Ce point n'a pas pu être posé sur la carte."
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(PANEL_FRAME, partial: "maps/comment_new_panel",
                                                                locals: { lat: lat, lng: lng, body: comment.body, error: error }),
                 status: :unprocessable_content
        end
        format.html { redirect_to map_path, alert: error }
      end
    end
  end

  def reply
    reply = @comment.reply!(author: current_user, body: body_param)
    root = reply.root
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append(helpers.dom_id(root, :messages), partial: "maps/comment_message", locals: { comment: reply }),
          turbo_stream.replace(helpers.dom_id(root, :reply_form), partial: "maps/comment_reply_form", locals: { root: root })
        ]
      end
      format.html { redirect_to map_path(feature: reply.map_feature_id) }
    end
  rescue ActiveRecord::RecordInvalid
    root = @comment.root
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(root, :reply_form), partial: "maps/comment_reply_form",
                                                                                     locals: { root: root, error: "Écrivez un message." }),
               status: :unprocessable_content
      end
      format.html { redirect_to map_path(feature: root.map_feature_id), alert: "Écrivez un message." }
    end
  end

  def resolve
    @comment.resolve!(by: current_user)
    respond_panel(@comment.map_feature, saved: true)
  end

  def reopen
    @comment.reopen!
    respond_panel(@comment.map_feature, saved: true)
  end

  def destroy
    return head :forbidden unless @comment.removable_by?(current_user)

    feature = @comment.map_feature
    @comment.remove!
    respond_to do |format|
      format.turbo_stream do
        if @comment.root?
          marker = helpers.tag.div(hidden: true, data: { feature_deleted: feature.id, layer_id: feature.map_layer_id })
          render turbo_stream: turbo_stream.update(PANEL_FRAME, marker)
        else
          render turbo_stream: turbo_stream.remove(helpers.dom_id(@comment))
        end
      end
      format.html { redirect_to map_path }
    end
  end

  private

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(active_primary: "map")
  end

  def get_comment
    @comment = MapComment.find(params[:id])
  end

  def body_param
    params.dig(:map_comment, :body)
  end

  # Illisible = nil : la validation GeoJSON du point le refuse.
  def coordinates
    [Float(params[:lat], exception: false), Float(params[:lng], exception: false)]
  end

  def respond_panel(feature, saved: false)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(PANEL_FRAME, partial: "maps/comment_panel",
                                                              locals: { feature: feature.reload, saved: saved })
      end
      format.html { redirect_to map_path(feature: feature.id) }
    end
  end
end
