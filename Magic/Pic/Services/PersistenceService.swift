import Foundation

class PersistenceService {
    static let shared = PersistenceService()

    private let fileManager = FileManager.default
    private let projectsFileName = "projects.json"
    private let presetsFileName = "edit_presets.json"

    private var projectsURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(projectsFileName)
    }

    private var backupURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("projects.backup.json")
    }

    private var presetsURL: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent(presetsFileName)
    }

    func save(projects: [PhotoProject]) {
        do {
            // Backup existing file before overwriting
            if fileManager.fileExists(atPath: projectsURL.path) {
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: projectsURL, to: backupURL)
            }

            let data = try JSONEncoder().encode(projects)
            try data.write(to: projectsURL, options: .atomic)
        } catch {
            print("Error saving projects: \(error)")
            // Restore backup on failure
            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.removeItem(at: projectsURL)
                try? fileManager.copyItem(at: backupURL, to: projectsURL)
            }
        }
    }

    func load() -> [PhotoProject] {
        guard fileManager.fileExists(atPath: projectsURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: projectsURL)
            return try JSONDecoder().decode([PhotoProject].self, from: data)
        } catch {
            print("Error loading projects: \(error), trying backup")
            // Try backup
            if fileManager.fileExists(atPath: backupURL.path),
               let data = try? Data(contentsOf: backupURL),
               let projects = try? JSONDecoder().decode([PhotoProject].self, from: data) {
                return projects
            }
            return []
        }
    }

    // Save a single project (update or append)
    func save(project: PhotoProject) {
        var projects = load()
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
        save(projects: projects)
    }

    func savePresets(_ presets: [EditPreset]) {
        do {
            let data = try JSONEncoder().encode(presets)
            try data.write(to: presetsURL, options: .atomic)
        } catch {
            print("Error saving presets: \(error)")
        }
    }

    func loadPresets() -> [EditPreset] {
        guard fileManager.fileExists(atPath: presetsURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: presetsURL)
            return try JSONDecoder().decode([EditPreset].self, from: data)
        } catch {
            print("Error loading presets: \(error)")
            return []
        }
    }
}
