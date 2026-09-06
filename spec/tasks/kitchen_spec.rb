require "rails_helper"
require "rake"

# Les deux tâches rake de la cuisine (epic #219, phase 7) : on vérifie ici le
# CÂBLAGE (la tâche existe, charge l'environnement et appelle son service) ; le
# comportement est couvert par `spec/services/kitchen/scheduled_emails_spec.rb`.
RSpec.describe "kitchen rake tasks", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("kitchen:weekly_digest")
  end

  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    original = $stdout
    $stdout = StringIO.new
    task.invoke
    $stdout.string
  ensure
    $stdout = original
  end

  it "kitchen:weekly_digest tourne et rend compte" do
    expect(run_task("kitchen:weekly_digest")).to include("[kitchen:weekly_digest]")
  end

  it "kitchen:bread_reminders tourne et rend compte" do
    expect(run_task("kitchen:bread_reminders")).to include("[kitchen:bread_reminders]")
  end
end
