# == Schema Information
#
# Table name: projects
#
#  id          :bigint           not null, primary key
#  deleted_at  :datetime
#  description :text
#  due_date    :date
#  name        :string
#  status      :string           default("active"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  human_id    :bigint           not null
#  team_id     :bigint
#
# Indexes
#
#  index_projects_on_human_id  (human_id)
#  index_projects_on_team_id   (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (human_id => humans.id)
#  fk_rails_...  (team_id => teams.id)
#
class Project < ApplicationRecord
  include Commentable

  # Où en est le projet. Volontairement court : un projet avance, attend ou est
  # fini ; le détail vit dans ses actions.
  STATUSES = %w[active paused done].freeze
  STATUS_LABELS = {
    "active" => "En cours",
    "paused" => "En pause",
    "done" => "Terminé"
  }.freeze

  belongs_to :human, optional: true
  # Le pôle qui porte le projet (Michael, 2026-10-19) : sa page liste ses
  # projets et leur avancement. Facultatif en base pour les projets d'avant ;
  # exigé dès qu'on enregistre le projet.
  belongs_to :team, optional: true
  has_many :bundles
  has_many :tasks, through: :bundles

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :description

  validates :name,
            presence: true,
            uniqueness: true
  validates :team, presence: { message: "doit être choisi : chaque projet appartient à un pôle" }
  validates :status, inclusion: { in: STATUSES }

  # La discussion du projet prévient qui le porte.
  def comment_recipients = [human&.user].compact
  def comment_label = "le projet « #{name} »"

  def status_label = STATUS_LABELS.fetch(status, status)
  def done? = status == "done"

  def tasks_canceled
    tasks.where(status: Task::STATUS_CANCELED)
  end

  def tasks_closed
    tasks.where(status: Task::STATUS_CLOSED)
  end

  def tasks_in_progress
    tasks.where(status: Task::STATUS_IN_PROGRESS)
  end

  def tasks_open
    tasks.where(status: Task::STATUS_OPEN)
  end
end
