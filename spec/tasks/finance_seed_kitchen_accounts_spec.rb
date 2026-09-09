require "rails_helper"
require "rake"

# Les deux comptes de charge de la cuisine (epic #269, phase 1). Sans eux, un
# ticket de courses n'a nulle part où se ranger, et le reporting de la phase 2
# n'a rien à lire.
RSpec.describe "finance:seed_kitchen_accounts" do
  before(:all) do
    Rake::Task.clear
    Claudy::Application.load_tasks
  end

  before { Rake::Task["finance:seed_kitchen_accounts"].reenable }

  def run_task
    Rake::Task["finance:seed_kitchen_accounts"].invoke
  end

  def rerun_task
    Rake::Task["finance:seed_kitchen_accounts"].reenable
    run_task
  end

  it "crée les deux comptes, en charges de classe 6" do
    expect { run_task }.to change(GeneralAccount, :count).by(2)

    repas = GeneralAccount.find_by(code: "600005")
    buffets = GeneralAccount.find_by(code: "600006")

    expect(repas.name).to eq("Achats cuisine — repas")
    expect(buffets.name).to eq("Achats cuisine — buffets et apéros")
    # La classe et la nature se déduisent du code : la tâche ne les force pas.
    expect([repas, buffets].map(&:klass)).to eq([6, 6])
    expect([repas, buffets].map(&:nature)).to eq(%w[expense expense])
    expect([repas, buffets].map(&:active)).to eq([true, true])
  end

  it "annonce ce qu'elle a fait" do
    expect { run_task }.to output(/600005.*600006/m).to_stdout
  end

  it "est idempotente" do
    run_task

    expect { rerun_task }.not_to change(GeneralAccount, :count)
  end

  it "préremplit le réglage avec les deux comptes" do
    run_task

    codes = Kitchen::Config.expense_accounts.map(&:code)
    expect(codes).to contain_exactly("600005", "600006")
  end

  # Un second passage ne doit pas ressusciter un périmètre retiré à la main.
  it "ne réécrit pas un réglage déjà édité" do
    run_task
    Setting.set(Kitchen::Config::EXPENSE_ACCOUNTS_KEY, "")

    rerun_task

    expect(Kitchen::Config.expense_accounts).to eq([])
  end

  # `600004 Petite restauration` est le vocabulaire du bar, pas celui de la
  # cuisine : la tâche ne le touche pas, même s'il existe déjà.
  it "ne touche pas au compte 600004" do
    petite = GeneralAccount.create!(code: "600004", name: "Petite restauration")

    run_task

    expect(petite.reload.name).to eq("Petite restauration")
    expect(Kitchen::Config.expense_accounts.map(&:code)).not_to include("600004")
  end
end
