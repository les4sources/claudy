require "rails_helper"
require "rake"

# Epic #248, phase 2 — la demande mensuelle. Dry-run par défaut : envoyer des
# emails par accident à des gens qui ne sont pas de la maison ne se rattrape pas.
RSpec.describe "consignment:request" do
  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before do
    Rake::Task["consignment:request"].reenable
    ActionMailer::Base.deliveries.clear
  end

  let!(:eline) do
    Consignor.create!(name: "Eline", email: "eline@example.com", settlement_mode: "invoice",
                      commission_percent: 20, starts_on: Date.new(2026, 1, 1))
  end
  let!(:bruno) do
    Consignor.create!(name: "Bruno", email: "bruno@example.com", settlement_mode: "transfer",
                      commission_percent: 20, iban: "BE68539007547034", starts_on: Date.new(2026, 1, 1))
  end

  def run_task(env = {})
    original_stdout = $stdout
    original_env = ENV.to_h.slice("MONTH", "APPLY", "RESEND")
    $stdout = StringIO.new.tap { |io| io.set_encoding(Encoding::UTF_8) }
    env.each { |k, v| ENV[k] = v }
    # Une tâche rake ne s'exécute qu'une fois par processus : sans ce
    # `reenable`, le second appel d'un même exemple ne ferait rien du tout.
    Rake::Task["consignment:request"].reenable
    Rake::Task["consignment:request"].invoke
    $stdout.string
  ensure
    %w[MONTH APPLY RESEND].each { |k| ENV.delete(k) }
    original_env.each { |k, v| ENV[k] = v }
    $stdout = original_stdout
  end

  it "n'écrit rien et n'envoie rien en dry-run" do
    expect {
      sortie = run_task("MONTH" => "2026-08")
      expect(sortie).to include("Rien n'a été écrit")
    }.not_to change { ConsignmentReport.count }

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "crée un relevé et un email par artisan actif avec APPLY=1" do
    expect {
      run_task("MONTH" => "2026-08", "APPLY" => "1")
    }.to change { ConsignmentReport.count }.by(2)

    expect(ActionMailer::Base.deliveries.map { |m| m.to.first })
      .to match_array(%w[eline@example.com bruno@example.com])
    expect(ConsignmentReport.pluck(:period_month).uniq).to eq([Date.new(2026, 8, 1)])
    expect(ConsignmentReport.pluck(:requested_at)).to all(be_present)
  end

  it "ne double ni le relevé ni l'email quand on rejoue" do
    run_task("MONTH" => "2026-08", "APPLY" => "1")
    ActionMailer::Base.deliveries.clear

    expect {
      run_task("MONTH" => "2026-08", "APPLY" => "1")
    }.not_to change { ConsignmentReport.count }

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "renvoie quand on le demande explicitement" do
    run_task("MONTH" => "2026-08", "APPLY" => "1")
    ActionMailer::Base.deliveries.clear

    run_task("MONTH" => "2026-08", "APPLY" => "1", "RESEND" => "1")

    expect(ActionMailer::Base.deliveries.size).to eq(2)
  end

  it "écarte un artisan désactivé" do
    bruno.update!(active: false)

    run_task("MONTH" => "2026-08", "APPLY" => "1")

    expect(ConsignmentReport.count).to eq(1)
    expect(ConsignmentReport.first.consignor).to eq(eline)
  end

  it "écarte un contrat terminé avant le mois" do
    eline.update!(ends_on: Date.new(2026, 6, 30))

    sortie = run_task("MONTH" => "2026-08", "APPLY" => "1")

    expect(ConsignmentReport.count).to eq(1)
    expect(sortie).to include("contrat hors période")
  end

  # Un artisan sans email reçoit quand même son relevé : le lien lui sera donné
  # de la main à la main, et l'écran admin le montrera.
  it "crée le relevé mais signale l'artisan sans adresse" do
    eline.update_column(:email, nil)

    sortie = run_task("MONTH" => "2026-08", "APPLY" => "1")

    expect(ConsignmentReport.count).to eq(2)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(sortie).to include("aucune adresse email")
  end

  it "refuse un mois illisible plutôt que d'en inventer un" do
    expect { run_task("MONTH" => "août") }.to raise_error(SystemExit)
  end
end
