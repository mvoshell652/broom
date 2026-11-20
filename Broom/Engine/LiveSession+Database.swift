import GRDB

extension LiveSession: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "sessions"
}
