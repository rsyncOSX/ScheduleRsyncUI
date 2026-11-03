//
//  ReadSchedule.swift
//  RsyncUI
//
//  Created by Thomas Evensen on 19/04/2021.
//

import Foundation
import OSLog

@MainActor
struct ReadSchedule {
    func readjsonfilecalendar(_ validprofiles: [String]) async -> [SchedulesConfigurations]? {
        let path = Homepath()
        Logger.process.debugThreadOnly("ReadSchedule: readjsonfilecalendar()")
        guard let fullpathmacserial = path.fullpathmacserial else { return nil }

        let fileURL = URL(fileURLWithPath: fullpathmacserial)
            .appendingPathComponent(SharedConstants().caldenarfilejson)

        do {
            let data = try await SharedJSONStorageReader.shared.decodeArray(
                DecodeSchedules.self,
                from: fileURL
            )

            return data.compactMap { element in
                let item = SchedulesConfigurations(element)
                if item.schedule == ScheduleType.once.rawValue,
                   let daterun = item.dateRun, daterun.en_date_from_string() < Date.now {
                    return nil
                } else {
                    if let profile = item.profile {
                        return validprofiles.contains(profile) ? item : nil
                    } else {
                        return item
                    }
                }
            }
        } catch {
            if (error as NSError).code != NSFileReadNoSuchFileError {
                path.propagateError(error: error)
            }
            let message = "ReadSchedule - read Calendar from permanent storage " +
                "\(fileURL.path) failed with error: some ERROR reading"
            Logger.process.debugMessageOnly(message)
        }
        return nil
    }
}
