# @label Fil de commentaires
#
# Le fil polymorphe de l'epic #242. Rien n'est écrit en base : la preview monte
# des objets en mémoire et remplace la seule chose qui irait interroger la base,
# l'association `comments`.
class Comments::ThreadComponentPreview < ViewComponent::Preview
  # L'état de départ de tout objet commentable.
  def empty
    render Comments::ThreadComponent.new(commentable: commentable([]), current_user: michael)
  end

  # Un échange à deux voix.
  def with_comments
    thread = [
      comment(1, stephanie, "Il manque le ticket du 12 août — tu l'as sous la main ?", 2.days.ago),
      comment(2, michael, "Je le scanne ce soir et je le pose ici.", 3.hours.ago)
    ]

    render Comments::ThreadComponent.new(commentable: commentable(thread), current_user: michael)
  end

  # Le formulaire d'ajout après une soumission vide.
  def with_error
    draft = Comment.new(author: michael)
    draft.body = ""
    draft.errors.add(:body, "ne peut pas être vide")

    render Comments::ThreadComponent.new(commentable: commentable([]), current_user: michael,
                                         comment: draft)
  end

  private

  def michael   = @michael   ||= User.new(id: 1, email: "michael@les4sources.be")
  def stephanie = @stephanie ||= User.new(id: 2, email: "stephanie@les4sources.be")

  def comment(id, author, text, at)
    Comment.new(id: id, author: author, created_at: at, updated_at: at).tap { |c| c.body = text }
  end

  # Un rassemblement dont le fil est fourni en dur — le composant ne demande à
  # l'association que `chronological` puis `includes`.
  def commentable(thread)
    Gathering.new(id: 42).tap do |gathering|
      gathering.define_singleton_method(:comments) { PreviewThread.new(thread) }
    end
  end

  PreviewThread = Struct.new(:records) do
    def chronological = self
    def includes(*) = records
  end
end
