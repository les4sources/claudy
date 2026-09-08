# Le fil de commentaires d'un objet (epic #242, phase 1). Un seul composant sert
# partout : la fiche d'un rassemblement aujourd'hui, un séjour, et demain une
# note de frais ou une facture — c'est l'objet qui change, pas le fil.
#
#   = render Comments::ThreadComponent.new(commentable: @gathering, current_user: current_user)
#
# Tout le fil vit dans un conteneur identifié (`Comment.thread_dom_id`) : le
# contrôleur y renvoie un Turbo Stream `replace` après chaque ajout, édition ou
# suppression, donc la page ne se recharge jamais.
class Comments::ThreadComponent < ViewComponent::Base
  # `rich_text_area` du form builder maison appelle `rich_textarea_tag`, un
  # helper d'ActionText qu'un composant n'a pas par défaut — sans ce include,
  # le formulaire du fil lève à l'affichage.
  include ActionText::TagHelper
  # …lequel construit l'URL d'upload direct via `main_app`, absent lui aussi du
  # contexte d'un composant.
  delegate :main_app, to: :helpers

  # `comment` : le brouillon du formulaire d'ajout — porte les erreurs quand une
  # soumission a échoué, sinon un commentaire vierge.
  #
  # L'édition d'un commentaire existant ne passe PAS par le serveur : chaque
  # ligne embarque son formulaire, masqué, qu'un contrôleur Stimulus dévoile.
  # Un aller-retour de moins, et aucune action `edit` à écrire.
  def initialize(commentable:, current_user:, comment: nil, title: "Commentaires")
    super()
    @commentable  = commentable
    @current_user = current_user
    @title        = title
    @comment      = comment || Comment.new(commentable: commentable)
  end

  attr_reader :commentable, :current_user, :comment, :title

  def dom_id = Comment.thread_dom_id(commentable)

  def comments = commentable.comments.chronological.includes(author: :human)

  def signed_in? = current_user.present?

  def avatar_url(comment)
    human = comment.author_human
    return nil unless human.respond_to?(:photo?) && human.photo?

    human.photo_url(:thumb)
  end

  # « il y a 3 jours », mais la date complète en infobulle : dans un fil de
  # discussion la fraîcheur compte plus que la date exacte, sans la perdre.
  def relative_time(time)
    "il y a #{helpers.time_ago_in_words(time)}"
  end

  def initials(comment)
    comment.author_label.to_s.split(/[\s@.]/).reject(&:blank?).first(2).map { |w| w[0] }.join.upcase
  end
end
