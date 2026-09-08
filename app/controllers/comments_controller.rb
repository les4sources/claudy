# Les commentaires polymorphes (epic #242, phase 1). Trois actions, une seule
# réponse : le fil complet, remplacé en Turbo Stream. La page appelante n'a rien
# à savoir de plus que « rends le composant ».
#
# Le type de l'objet commenté vient du formulaire. Il est résolu par la LISTE
# BLANCHE `Comment::COMMENTABLE_TYPES`, jamais par un `constantize` libre : un
# paramètre forgé ne doit pas pouvoir instancier une classe au hasard.
class CommentsController < BaseController
  before_action :get_comment, only: %i[update destroy]
  before_action :authorize_author!, only: %i[update destroy]

  def create
    @commentable = resolve_commentable
    return head :not_found if @commentable.nil?

    @comment = @commentable.comments.build(body: body_param, author: current_user)

    if @comment.save
      render_thread
    else
      render_thread(draft: @comment, status: :unprocessable_entity)
    end
  end

  def update
    @commentable = @comment.commentable

    if @comment.update(body: body_param)
      render_thread
    else
      render_thread(status: :unprocessable_entity)
    end
  end

  def destroy
    @commentable = @comment.commentable
    @comment.soft_delete!(validate: false)
    render_thread
  end

  private

  def get_comment
    @comment = Comment.find(params[:id])
  end

  # Un utilisateur ne touche qu'à ses commentaires ; un admin global peut
  # intervenir sur tout le fil (`Comment#editable_by?`).
  def authorize_author!
    return if @comment.editable_by?(current_user)

    head :forbidden
  end

  # Le type demandé DOIT figurer dans la liste blanche, sinon 404 : ni message
  # d'erreur bavard, ni classe instanciée. Un objet introuvable donne le même
  # 404 — un type valide ne doit pas se distinguer d'un type refusé.
  def resolve_commentable
    type = params.dig(:comment, :commentable_type).to_s
    return nil unless Comment::COMMENTABLE_TYPES.include?(type)

    type.constantize.find_by(id: params.dig(:comment, :commentable_id))
  end

  def body_param = params.require(:comment).permit(:body)[:body]

  # Une seule sortie : le fil entier, remplacé sur place. En Turbo Stream quand
  # le navigateur le demande, sinon un retour à la page de l'objet — le fil
  # reste utilisable sans JavaScript.
  def render_thread(draft: nil, status: :ok)
    respond_to do |format|
      format.turbo_stream do
        thread = render_to_string(
          Comments::ThreadComponent.new(commentable: @commentable,
                                        current_user: current_user,
                                        comment: draft),
          layout: false
        )
        render turbo_stream: turbo_stream.replace(Comment.thread_dom_id(@commentable), thread),
               status: status
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new
  end
end
