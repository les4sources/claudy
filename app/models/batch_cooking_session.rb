# == Schema Information
#
# Table name: batch_cooking_sessions
#
#  id             :bigint           not null, primary key
#  cooked_on      :date             not null
#  deleted_at     :datetime
#  label          :string
#  meals_count    :integer          default(5), not null
#  notes          :text
#  total_portions :integer          default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  created_by_id  :bigint
#
# Indexes
#
#  index_batch_cooking_sessions_on_cooked_on      (cooked_on)
#  index_batch_cooking_sessions_on_created_by_id  (created_by_id)
#  index_batch_cooking_sessions_on_deleted_at     (deleted_at)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#

# Une session de batch cooking (epic #246).
#
# Un repas préparé pour les sourciers : chaque famille servie paie 5 € la
# portion, chaque cuisinier volontaire gagne 3,50 € la portion préparée. La
# session porte les DEUX listes — qui a mangé, qui a cuisiné — et rien d'autre.
#
# ELLE NE PORTE AUCUN MONTANT. Les écritures se génèrent depuis ces lignes par
# `Finance::RecordBatchCooking`, à la date de la session et au tarif de ce
# jour-là. Stocker ici un total en euros reviendrait à avoir deux vérités dont
# une finirait par mentir.
#
# LA SAISIE PARLE EN PERSONNES ET EN REPAS (issue #307). Une session prépare
# `meals_count` repas — 5 en général — et chaque ménage servi déclare son
# NOMBRE DE PERSONNES. Les portions d'une famille s'en déduisent :
# `meals_count × people`. On part du constat que chaque famille prend tous les
# repas de la session, donc le nombre de repas ne se surcharge pas ligne par
# ligne. Demander des portions revenait à demander une multiplication à
# quelqu'un qui a les mains dans la farine — et la première session réelle est
# partie facturée cinq fois trop bas.
#
# `total_portions` est la seule redondance assumée : le total des portions
# SERVIES, tenu à jour depuis les lignes, parce que la liste des sessions
# l'affiche et qu'un recalcul par ligne d'écran ferait une requête par session.
class BatchCookingSession < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :created_by, class_name: "User", optional: true

  has_many :servings, class_name: "BatchCookingServing",
                      foreign_key: :batch_cooking_session_id,
                      inverse_of: :session, dependent: :destroy
  has_many :cooks, class_name: "BatchCookingCook",
                   foreign_key: :batch_cooking_session_id,
                   inverse_of: :session, dependent: :destroy
  has_many :member_accounts, through: :servings
  has_many :humans, through: :cooks

  # Une ligne sans personne n'est pas une erreur : c'est un ménage qu'on n'a pas
  # servi, ou un cuisinier qu'on n'a pas retenu. On la jette silencieusement
  # plutôt que de refuser tout le formulaire.
  accepts_nested_attributes_for :servings, allow_destroy: true,
                                           reject_if: ->(attrs) { attrs["people"].to_i <= 0 }
  accepts_nested_attributes_for :cooks, allow_destroy: true,
                                        reject_if: ->(attrs) { attrs["human_id"].blank? }

  validates :cooked_on, presence: true
  # Une session sans repas ne facture rien. Zéro n'est pas une session vide :
  # c'est une saisie qu'on n'a pas finie, et elle doit se voir.
  validates :meals_count, presence: true,
                          numericality: { only_integer: true, greater_than: 0 }

  scope :recent_first, -> { order(cooked_on: :desc, id: :desc) }
  scope :chronological, -> { order(cooked_on: :asc, id: :asc) }

  # Déclaré APRÈS les associations : les rappels d'autosauvegarde d'une
  # `has_many` sont posés à la déclaration de l'association, donc celui-ci
  # s'exécute une fois les lignes filles écrites. Déclaré avant, il compterait
  # les portions de l'état précédent.
  after_save :refresh_total_portions!

  # Les PERSONNES servies, toutes familles confondues. C'est la quantité que
  # Stéphanie a sous les yeux, et c'est aussi celle que se partagent les
  # cuisiniers (voir `even_split`) : leur rémunération ne suit PAS le
  # multiplicateur « repas », décision gelée jusqu'à une issue dédiée.
  def people_served = servings.sum(:people)

  # Les portions réellement servies : chaque famille prend tous les repas.
  def portions_served = meals_count.to_i * people_served

  def portions_cooked = cooks.sum(&:portions)

  # Ce que la session facture aux ménages, au tarif figé sur les écritures
  # quand elles existent — sinon au tarif du jour de la session.
  def households_count = servings.size

  def cooks_count = cooks.size

  # Une session se nomme par sa DATE. Le nom de plat a été retiré de la saisie
  # (décision de Michael) : un batch cooking prépare plusieurs plats d'un coup,
  # et Steph les annonce sur Slack. La colonne `label` reste en base, sans
  # interface — rien ne l'écrit plus.
  def title = "Batch cooking du #{I18n.l(cooked_on, format: :ddmmyyyy)}"

  # Répartition à parts égales des portions servies entre les cuisiniers. Sert
  # de proposition à la saisie : chaque ligne reste modifiable.
  #
  # Le partage se fait au MILLIÈME de portion, pas à l'entier : cinq portions
  # entre deux personnes font deux parts et demie, et arrondir en ferait perdre
  # 1,75 € à quelqu'un. Le reliquat va aux premiers, si bien que la somme des
  # parts vaut toujours exactement le total.
  def self.even_split(total_portions, cooks_count)
    count = cooks_count.to_i
    return [] if count <= 0

    milli = (BigDecimal(total_portions.to_s) * 1_000).round
    base, remainder = milli.divmod(count)

    Array.new(count) { |index| (BigDecimal(base + (index < remainder ? 1 : 0)) / 1_000) }
  end

  # Recompté depuis les lignes, jamais incrémenté : un compteur qu'on incrémente
  # dérive dès la première ligne supprimée en dehors du formulaire.
  def refresh_total_portions!
    return if destroyed? || new_record?

    total = meals_count.to_i * servings.reload.sum(:people)
    return if total == total_portions

    update_column(:total_portions, total)
  end
end
