import Foundation

extension PCMPlaybackBackend {
    func rampPresentationGain(
        to target: Float,
        duration: Duration,
        generation: Int
    ) async {
        let target = min(max(target, 0), 1)
        guard generation == gainRampGeneration,
              !Task.isCancelled
        else {
            return
        }

        let start = presentationGain
        guard duration > .zero, start != target else {
            presentationGain = target
            applyGain()
            return
        }

        let stepCount = PCMGainAutomation.stepCount(for: duration)
        let stepDuration = duration / stepCount
        for step in 1 ... stepCount {
            do {
                try await Task.sleep(for: stepDuration)
            } catch {
                return
            }
            guard generation == gainRampGeneration,
                  !Task.isCancelled
            else {
                return
            }
            let progress = Float(step) / Float(stepCount)
            presentationGain = start + (target - start) * progress
            applyGain()
        }
    }

    func rampCrossfadeTreble(
        to target: Float,
        duration: Duration,
        generation: Int
    ) async {
        let start = crossfadeTrebleOpenness
        let stepCount = PCMGainAutomation.stepCount(for: duration)
        let stepDuration = duration / stepCount
        for step in 1 ... stepCount {
            do {
                try await Task.sleep(for: stepDuration)
            } catch {
                return
            }
            guard generation == trebleRampGeneration,
                  !Task.isCancelled
            else {
                return
            }
            let progress = Float(step) / Float(stepCount)
            crossfadeTrebleOpenness = start + (target - start) * progress
            applyCrossfadeTreble()
        }
    }

    func cancelTrebleRamp() {
        trebleRampTask?.cancel()
        trebleRampTask = nil
        trebleRampGeneration &+= 1
    }
}
