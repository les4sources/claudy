require "rails_helper"

# Les projets d'un pôle sur sa page (Michael, 2026-10-19) : avancement des
# actions, projets en retard, prochaines actions.
RSpec.describe Teams::ProjectBoard do
  let(:today) { Date.new(2026, 10, 19) }
  let(:team) { Team.create!(name: "Pôle Espaces verts") }
  let(:porteuse) { Human.create!(name: "Malau") }

  subject(:board) { described_class.new(team: team, today: today) }

  def project(name, team: self.team, **attrs)
    Project.create!(name: name, team: team, human: porteuse, **attrs).tap do |p|
      p.bundles.create!(name: "Actions du projet", position: 0)
    end
  end

  def task(project, name, status: nil, due_date: nil)
    Task.create!(name: name, project: project, bundle: project.bundles.first, status: status, due_date: due_date)
  end

  it "compte les actions faites sur les actions non annulées, et celles en retard" do
    poulailler = project("Poulailler")
    task(poulailler, "Plans", status: Task::STATUS_CLOSED)
    task(poulailler, "Matériaux", due_date: today - 1)
    task(poulailler, "Construction", status: Task::STATUS_IN_PROGRESS, due_date: today + 10)
    task(poulailler, "Peinture", status: Task::STATUS_CANCELED, due_date: today - 5)

    row = board.ongoing.first
    expect([row.done_count, row.total_count, row.overdue_count]).to eq([1, 3, 1])
    expect(row.percent).to eq(33)
  end

  it "met les projets en cours avant ceux en pause, l'échéance la plus proche d'abord, et range les terminés à part" do
    project("Sans échéance")
    project("Lointain", due_date: today + 90)
    project("Proche", due_date: today + 5)
    project("En pause", status: "paused", due_date: today + 1)
    project("Fini", status: "done")

    expect(board.ongoing.map { |row| row.project.name }).to eq(["Proche", "Lointain", "Sans échéance", "En pause"])
    expect(board.finished.map { |row| row.project.name }).to eq(["Fini"])
    expect(board.counts).to eq("active" => 3, "paused" => 1, "done" => 1)
  end

  it "signale un projet dont l'échéance est passée, sauf s'il est terminé" do
    project("En retard", due_date: today - 1)
    project("Fini en retard", status: "done", due_date: today - 1)

    expect(board.ongoing.first.late?).to be(true)
    expect(board.finished.first.late?).to be(false)
  end

  it "liste les prochaines actions des projets en cours, la plus urgente d'abord" do
    actif = project("Actif")
    en_pause = project("En pause", status: "paused")
    task(actif, "Plus tard", due_date: today + 30)
    task(actif, "Sans date")
    task(actif, "Urgent", due_date: today - 2)
    task(actif, "Déjà fait", status: Task::STATUS_CLOSED, due_date: today - 3)
    task(en_pause, "En attente", due_date: today)

    expect(board.upcoming_tasks.map(&:name)).to eq(["Urgent", "Plus tard", "Sans date"])
  end

  it "voit aussi les projets des pôles qu'il regroupe, et pas ceux des autres pôles" do
    enfant = Team.create!(name: "Pôle Verger", parent: team)
    project("Verger", team: enfant)
    project("Ailleurs", team: Team.create!(name: "Pôle Accueil"))

    expect(board.ongoing.map { |row| row.project.name }).to eq(["Verger"])
    expect(board.sub_teams?).to be(true)
    expect(described_class.new(team: enfant, today: today).ongoing.size).to eq(1)
  end
end
