# Rend un modèle commentable (epic #242, décision 1). Ajouter le concern suffit ;
# les deux seules choses à surcharger sont `comment_recipients` — la liste des
# `User` à prévenir, utilisée par `Notifications::CommentPosted` depuis la phase
# 2 — et `comment_label`, le nom de l'objet dans le titre de la notification.
#
#   class Gathering < ApplicationRecord
#     include Commentable
#   end
#
# Le type doit aussi figurer dans `Comment::COMMENTABLE_TYPES`, sinon le
# commentaire est refusé : la liste blanche est le garde-fou du contrôleur.
module Commentable
  extend ActiveSupport::Concern

  included do
    has_many :comments, as: :commentable, dependent: :destroy
  end

  # Destinataires déclarés par le modèle, en plus des auteurs des commentaires
  # précédents (décision 4). Vide par défaut.
  def comment_recipients
    []
  end

  # Comment cet objet se nomme dans le titre d'une notification (« a commenté
  # LE SÉJOUR DE MARTIN »). Surchargeable ; repli sur le nom du modèle.
  def comment_label
    self.class.model_name.human.downcase
  end
end
