# frozen_string_literal: true

module Projects
  # La page d'un projet dans la nouvelle interface (Michael 2026-10-24,
  # « s'inspirer de Basecamp ») : ses groupes d'actions comme des listes à
  # cocher, chacune avec son avancement et ses actions faites repliées en bas,
  # puis à côté où en est le projet et qui s'y active.
  class Sheet
    UPCOMING_LIMIT = 4

    # Un groupe d'actions : ses actions à faire (en cours d'abord, puis par
    # échéance) et ses actions faites. Les annulées ne s'affichent pas.
    List = Struct.new(:bundle, :open_tasks, :done_tasks, keyword_init: true) do
      def done_count = done_tasks.size
      def total_count = open_tasks.size + done_tasks.size
      def percent = total_count.zero? ? 0 : (done_count * 100.0 / total_count).round
    end

    # Une personne du projet et ce qui lui reste à faire.
    Person = Struct.new(:human, :carrier, :open_count, keyword_init: true)

    attr_reader :project, :today

    def initialize(project:, today: Date.current)
      @project = project
      @today = today
    end

    def lists
      @lists ||= bundles.map do |bundle|
        tasks = bundle.tasks.reject { |task| task.status == TaskStats::CANCELED }
        open, done = tasks.partition { |task| TaskStats.open?(task) }
        List.new(bundle: bundle, open_tasks: sort_open(open), done_tasks: done.sort_by { |task| -task.updated_at.to_i })
      end
    end

    def done_count = lists.sum(&:done_count)
    def total_count = lists.sum(&:total_count)
    def open_count = total_count - done_count
    def percent = total_count.zero? ? 0 : (done_count * 100.0 / total_count).round

    def overdue_tasks = open_tasks.select { |task| late?(task) }
    def late?(task) = task.due_date.present? && task.due_date < today && TaskStats.open?(task)
    def project_late? = project.due_date.present? && project.due_date < today && !project.done?

    # Les prochaines échéances, la plus proche d'abord.
    def upcoming
      open_tasks.select(&:due_date).sort_by { |task| [task.due_date, task.id] }.first(UPCOMING_LIMIT)
    end

    # Qui porte le projet, puis à qui des actions ouvertes sont confiées.
    def people
      @people ||= begin
        counts = Hash.new(0)
        open_tasks.each { |task| task.humans.each { |human| counts[human] += 1 } }
        carrier = project.human ? [Person.new(human: project.human, carrier: true, open_count: counts.delete(project.human).to_i)] : []
        carrier + counts.sort_by { |human, _| human.name.to_s.downcase }
                        .map { |human, count| Person.new(human: human, carrier: false, open_count: count) }
      end
    end

    private

    def bundles
      project.bundles.includes(tasks: :humans).order(Arel.sql("bundles.position IS NULL, bundles.position, bundles.id")).to_a
    end

    def open_tasks = lists.flat_map(&:open_tasks)

    def sort_open(tasks)
      tasks.sort_by do |task|
        [task.status == Task::STATUS_IN_PROGRESS ? 0 : 1, task.due_date || Date.new(9999), task.id]
      end
    end
  end
end
