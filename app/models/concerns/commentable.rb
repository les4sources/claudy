# Rend un modèle commentable (epic #242, décision 1). Ajouter le concern suffit ;
# la seule chose à surcharger, plus tard, est `comment_recipients` — la liste des
# `User` à prévenir, que la phase 2 utilisera pour notifier.
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
  # précédents (décision 4). Vide par défaut ; branché en phase 2.
  def comment_recipients
    []
  end
end
