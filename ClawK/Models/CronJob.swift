//
//  CronJob.swift
//  ClawK
//
//  Cron job model matching gateway API response
//

import Foundation

struct CronJob: Codable, Identifiable {
    let id: String
    let agentId: String?
    let name: String
    let enabled: Bool?
    let createdAtMs: Int64?
    let updatedAtMs: Int64?
    let schedule: CronSchedule
    let sessionTarget: String?
    let wakeMode: String?
    let payload: CronPayload?
    let state: CronState?
    let isolation: CronIsolation?
    let description: String?
    let deleteAfterRun: Bool?
    let delivery: CronDelivery?
    
    var isEnabled: Bool {
        enabled ?? true
    }
    
    var isRunning: Bool {
        // A job is "running" if it was started recently and hasn't finished
        // We approximate this by checking if lastRunAtMs is recent and no new nextRunAtMs
        guard let state = state else { return false }
        guard let lastRun = state.lastRunAtMs else { return false }
        
        let now = Date().timeIntervalSince1970 * 1000
        let timeSinceLastRun = now - Double(lastRun)
        
        // If it ran in the last 5 minutes and duration suggests it might still be running
        if let duration = state.lastDurationMs {
            return timeSinceLastRun < Double(duration) + 60000 // Add 1 minute buffer
        }
        
        // Fallback: running if started less than 10 minutes ago
        return timeSinceLastRun < 600000
    }
    
    var nextRunDate: Date? {
        guard let ms = state?.nextRunAtMs else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }
    
    var lastRunDate: Date? {
        guard let ms = state?.lastRunAtMs else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }
    
    var scheduleDescription: String {
        switch schedule.kind {
        case "cron":
            return schedule.expr ?? "cron"
        case "every":
            if let ms = schedule.everyMs {
                return formatDuration(ms)
            }
            return "interval"
        case "at":
            if let ms = schedule.atMs {
                let date = Date(timeIntervalSince1970: Double(ms) / 1000)
                return formatDate(date)
            }
            return "one-time"
        default:
            return schedule.kind
        }
    }
    
    var modelName: String? {
        payload?.model
    }
    
    private func formatDuration(_ ms: Int64) -> String {
        let seconds = ms / 1000
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        
        if days > 0 { return "\(days)d" }
        if hours > 0 { return "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct CronSchedule: Codable {
    let kind: String
    let expr: String?
    let tz: String?
    let everyMs: Int64?
    let atMs: Int64?
}

struct CronPayload: Codable {
    let kind: String
    let message: String?
    let text: String?
    let deliver: Bool?
    let bestEffortDeliver: Bool?
    let channel: String?
    let to: String?
    let model: String?
    let thinking: String?
}

struct CronState: Codable {
    let nextRunAtMs: Int64?
    let lastRunAtMs: Int64?
    let lastStatus: String?
    let lastDurationMs: Int64?
    let consecutiveErrors: Int?
}

struct CronDelivery: Codable {
    let mode: String?
    let channel: String?
    let to: String?
    let bestEffort: Bool?
}

struct CronIsolation: Codable {
    let postToMainPrefix: String?
    let postToMainMode: String?
    let postToMainMaxChars: Int?
}

// MARK: - API Response
struct CronListResponse: Codable {
    let jobs: [CronJob]
}
