# Un projet appartient à un pôle (Michael, 2026-10-19) : c'est depuis la page du
# pôle qu'on suit ses projets. La colonne reste nullable pour les projets déjà
# en base ; le formulaire, lui, exige le pôle.
class AddTeamAndStatusToProjects < ActiveRecord::Migration[8.1]
  def change
    add_reference :projects, :team, foreign_key: true, null: true
    add_column :projects, :status, :string, null: false, default: "active"
  end
end
