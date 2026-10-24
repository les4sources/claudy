# frozen_string_literal: true

module Projects
  # Comment on compte les actions d'un projet, partout où on le montre (page
  # d'un pôle, page Projets, page du projet).
  #
  # Une action compte quand elle est rangée dans un groupe encore vivant du
  # projet : c'est ce que la page du projet affiche. Elle est faite quand elle
  # est « Terminée » ; « Annulée », elle ne compte ni dans le fait ni dans le
  # total. Sans statut (celles qu'on ajoute depuis la page du projet), elle est
  # à faire.
  module TaskStats
    DONE = Task::STATUS_CLOSED
    CANCELED = Task::STATUS_CANCELED

    module_function

    def live_tasks(project_ids)
      Task.where(project_id: project_ids, bundle_id: Bundle.where(project_id: project_ids).select(:id))
    end

    def open_tasks(project_ids)
      live_tasks(project_ids).where("tasks.status IS NULL OR tasks.status NOT IN (?)", [DONE, CANCELED])
    end

    def open?(task) = ![DONE, CANCELED].include?(task.status)

    # Une requête pour tous les projets : { id => [faites, total, en retard] }.
    def counts(project_ids, today: Date.current)
      return {} if project_ids.empty?

      live_tasks(project_ids)
        .group(:project_id)
        .pluck(
          :project_id,
          Arel.sql("COUNT(*) FILTER (WHERE tasks.status = '#{DONE}')"),
          Arel.sql("COUNT(*) FILTER (WHERE tasks.status IS DISTINCT FROM '#{CANCELED}')"),
          Arel.sql(Task.sanitize_sql_array([
            "COUNT(*) FILTER (WHERE (tasks.status IS NULL OR tasks.status NOT IN (?, ?)) AND tasks.due_date < ?)",
            DONE, CANCELED, today
          ]))
        )
        .to_h { |id, done, total, overdue| [id, [done, total, overdue]] }
    end

    # Les personnes à qui des actions encore ouvertes sont confiées, par projet :
    # { id => [Human, …] }, dans l'ordre alphabétique.
    def assignees(project_ids)
      return {} if project_ids.empty?

      pairs = open_tasks(project_ids).joins(:humans).distinct.pluck(:project_id, "humans.id")
      humans = Human.where(id: pairs.map(&:last).uniq).index_by(&:id)
      pairs.group_by(&:first).transform_values do |list|
        list.filter_map { |_, human_id| humans[human_id] }.sort_by { |human| human.name.to_s.downcase }
      end
    end
  end
end
