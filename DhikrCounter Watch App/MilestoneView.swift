import SwiftUI

struct MilestoneView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Current milestone display
                    CurrentMilestoneView()
                    
                    // Milestone progress cards
                    MilestoneProgressView()
                    
                    // Dhikr type information
                    DhikrTypeInfoView()
                }
                .padding()
            }
            .navigationTitle("Milestones")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CurrentMilestoneView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    var body: some View {
        VStack(spacing: 12) {
            // Current count with progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: detectionEngine.progressValue)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: detectionEngine.progressValue)
                
                VStack {
                    Text("\(detectionEngine.pinchCount)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("dhikr")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Next milestone info
            Text(detectionEngine.milestoneText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(16)
    }
}

struct MilestoneProgressView: View {
    @EnvironmentObject var detectionEngine: DhikrDetectionEngine
    
    let milestones = [
        MilestoneInfo(count: 33, title: "First Third", subtitle: "Subhan Allah", description: "Glory to Allah"),
        MilestoneInfo(count: 66, title: "Second Third", subtitle: "Alhamdulillah", description: "Praise to Allah"),
        MilestoneInfo(count: 100, title: "Complete", subtitle: "Allahu Akbar", description: "Allah is Greatest")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Progress Milestones")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                ForEach(Array(milestones.enumerated()), id: \.element.count) { index, milestone in
                    MilestoneCard(
                        milestone: milestone,
                        isCompleted: detectionEngine.pinchCount >= milestone.count,
                        isCurrent: isCurrentMilestone(index: index)
                    )
                }
            }
        }
    }
    
    private func isCurrentMilestone(index: Int) -> Bool {
        let currentCount = detectionEngine.pinchCount
        
        if index == 0 && currentCount < 33 {
            return true
        } else if index == 1 && currentCount >= 33 && currentCount < 66 {
            return true
        } else if index == 2 && currentCount >= 66 && currentCount < 100 {
            return true
        }
        
        return false
    }
}

struct MilestoneCard: View {
    let milestone: MilestoneInfo
    let isCompleted: Bool
    let isCurrent: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Milestone indicator
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 40, height: 40)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                } else {
                    Text("\(milestone.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isCurrent ? .white : .secondary)
                }
            }
            
            // Milestone info
            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(milestone.subtitle)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isCurrent ? .green : .secondary)
                
                Text(milestone.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? Color.green : Color.clear, lineWidth: 2)
        )
    }
    
    private var backgroundColor: Color {
        if isCompleted {
            return .green
        } else if isCurrent {
            return .green
        } else {
            return Color.gray.opacity(0.4)
        }
    }
    
    private var cardBackground: Color {
        if isCurrent {
            return Color.green.opacity(0.1)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
}

struct DhikrTypeInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About Dhikr")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                DhikrInfoCard(
                    title: "Tasbih (33×)",
                    arabic: "سُبْحَانَ ٱللَّٰهِ",
                    translation: "Subhan Allah",
                    meaning: "Glory to Allah"
                )
                
                DhikrInfoCard(
                    title: "Tahmid (33×)",
                    arabic: "ٱلْحَمْدُ لِلَّٰهِ",
                    translation: "Alhamdulillah",
                    meaning: "Praise to Allah"
                )
                
                DhikrInfoCard(
                    title: "Takbir (34×)",
                    arabic: "ٱللَّٰهُ أَكْبَرُ",
                    translation: "Allahu Akbar",
                    meaning: "Allah is Greatest"
                )
            }
        }
    }
}

struct DhikrInfoCard: View {
    let title: String
    let arabic: String
    let translation: String
    let meaning: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Text(arabic)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(translation)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text(meaning)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
    }
}

struct MilestoneInfo {
    let count: Int
    let title: String
    let subtitle: String
    let description: String
}

// MARK: - Preview

struct MilestoneView_Previews: PreviewProvider {
    static var previews: some View {
        MilestoneView()
            .environmentObject(DhikrDetectionEngine())
    }
}