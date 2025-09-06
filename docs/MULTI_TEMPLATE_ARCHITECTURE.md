# Multi-Template Architecture Design

**Status**: Design phase - not yet implemented  
**Prerequisites**: Current single-template system (see CURRENT_STATE.md)

## Overview

Enhance the TKEO detector to support multiple template sets for improved detection across different pinch types, contexts, and user scenarios.

## Benefits of Multiple Template Sets

### **1. Pinch Type Diversity**
- **Light pinches**: Subtle finger movements, low amplitude patterns
- **Strong pinches**: Forceful gestures, high amplitude patterns  
- **Fast pinches**: Quick taps, sharp transients
- **Slow pinches**: Sustained pressure, longer duration patterns

### **2. Context Adaptation**
- **Stationary templates**: Sitting, standing still (current system)
- **Walking templates**: Motion compensation patterns
- **Hand position variants**: Different wrist angles, orientations

### **3. Temporal Diversity**
- **Fresh templates**: Recent high-quality sessions
- **Historical templates**: Proven patterns over time
- **Seasonal templates**: Activity patterns that change over time

## Architecture Design

### **Template Collection System**

```python
class TemplateCollection:
    """Manages multiple template sets with metadata and selection strategies"""
    
    def __init__(self):
        self.template_sets = {}  # Dict[str, TemplateSet]
        self.selection_strategy = "best_match"  # or "ensemble", "weighted"
        
    def add_template_set(self, name: str, template_set: TemplateSet):
        """Add a named template set to the collection"""
        
    def get_active_templates(self, context: Dict) -> List[TemplateSet]:
        """Select templates based on current context/strategy"""
        
    def merge_template_sets(self, sets: List[str]) -> TemplateSet:
        """Combine multiple template sets into one"""

class TemplateSet:
    """Enhanced template set with metadata and quality metrics"""
    
    def __init__(self):
        self.templates = []  # List of fusion score patterns
        self.metadata = {
            'source_session': str,      # Original session file
            'creation_date': datetime,   # When templates were created
            'template_type': str,        # 'light', 'strong', 'walking', etc.
            'quality_score': float,      # Overall template set quality
            'usage_count': int,          # How often used in production
            'success_rate': float,       # Detection success rate with these templates
            'context_tags': List[str]    # ['stationary', 'morning', 'home', etc.]
        }
        
    def evaluate_quality(self) -> float:
        """Assess template set quality based on diversity and coherence"""
        
    def update_performance_metrics(self, detection_results):
        """Update usage statistics based on detection performance"""
```

### **Template Storage Format**

```json
{
  "format_version": "2.0",
  "collection_metadata": {
    "user_id": "optional_user_identifier",
    "created": "2025-01-09T10:30:00",
    "last_updated": "2025-01-09T15:45:00",
    "total_template_sets": 5
  },
  "template_sets": {
    "stationary_light": {
      "templates": [[0.1, 0.2, ...], [0.15, 0.25, ...], ...],
      "metadata": {
        "source_session": "training_light_pinches.csv",
        "template_type": "light",
        "quality_score": 0.85,
        "context_tags": ["stationary", "light", "morning"],
        "creation_date": "2025-01-09T10:30:00",
        "usage_count": 45,
        "success_rate": 0.78
      }
    },
    "stationary_strong": {
      "templates": [[0.3, 0.6, ...], [0.4, 0.7, ...], ...],
      "metadata": {
        "source_session": "training_strong_pinches.csv", 
        "template_type": "strong",
        "quality_score": 0.92,
        "context_tags": ["stationary", "strong", "deliberate"],
        "creation_date": "2025-01-09T11:15:00",
        "usage_count": 23,
        "success_rate": 0.89
      }
    },
    "walking_mixed": {
      "templates": [[0.2, 0.4, ...], [0.25, 0.45, ...], ...],
      "metadata": {
        "source_session": "training_walking_pinches.csv",
        "template_type": "walking",
        "quality_score": 0.71,
        "context_tags": ["walking", "motion", "mixed"],
        "creation_date": "2025-01-09T14:20:00", 
        "usage_count": 12,
        "success_rate": 0.65
      }
    }
  },
  "selection_config": {
    "strategy": "best_match",
    "fallback_strategy": "ensemble", 
    "quality_threshold": 0.6,
    "max_active_sets": 3
  }
}
```

### **Template Selection Strategies**

#### **1. Best Match Strategy** (Default)
```python
def select_best_match(self, detection_context):
    """Select single highest-quality template set matching context"""
    # Match context tags, prioritize by quality_score + success_rate
    # Use most recent high-quality set
```

#### **2. Ensemble Strategy**  
```python
def select_ensemble(self, detection_context):
    """Use multiple template sets simultaneously"""
    # Run NCC against templates from multiple sets
    # Take max NCC score across all template sets
    # Weight by template set quality scores
```

#### **3. Weighted Strategy**
```python
def select_weighted(self, detection_context):
    """Combine templates from multiple sets with weights"""
    # Create weighted average templates from multiple sets
    # Weight by quality_score * success_rate * context_match
```

### **Training Workflow Enhancement**

#### **Multi-Session Training**
```bash
# Collect templates from multiple training sessions
python tkeo_pinch_detector.py --input light_pinches.csv --analysis-results analysis_light/ --save-templates --template-type light
python tkeo_pinch_detector.py --input strong_pinches.csv --analysis-results analysis_strong/ --save-templates --template-type strong  
python tkeo_pinch_detector.py --input walking_pinches.csv --analysis-results analysis_walking/ --save-templates --template-type walking

# Merge into multi-template collection
python tkeo_pinch_detector.py --merge-templates light_templates.json strong_templates.json walking_templates.json --output master_templates.json
```

#### **Incremental Training**
```bash
# Add new template set to existing collection
python tkeo_pinch_detector.py --input new_session.csv --analysis-results analysis_new/ --add-to-collection master_templates.json --template-type evening
```

### **Detection Enhancement**

#### **Context-Aware Selection**
```python
# Production detection with context
python tkeo_pinch_detector.py --input session.csv --template-collection master_templates.json --context '{"activity": "walking", "time": "morning"}'
```

#### **Adaptive Template Selection**
- **Motion detection**: Choose walking vs stationary template sets
- **Signal amplitude**: Select light vs strong template sets
- **Time of day**: Use temporal pattern preferences
- **Performance feedback**: Adapt selection based on detection success

### **Template Management Commands**

```bash
# Template collection management
python tkeo_pinch_detector.py --list-template-sets master_templates.json
python tkeo_pinch_detector.py --remove-template-set master_templates.json --set-name old_walking
python tkeo_pinch_detector.py --analyze-template-quality master_templates.json
python tkeo_pinch_detector.py --optimize-collection master_templates.json --max-sets 5

# Template performance analysis  
python tkeo_pinch_detector.py --template-performance-report master_templates.json
python tkeo_pinch_detector.py --recommend-training master_templates.json  # Suggest what template types to add
```

## Implementation Priority

### **Phase 1: Core Multi-Template Support**
1. **Template Collection Classes**: TemplateCollection, TemplateSet
2. **Storage Format**: Enhanced JSON with metadata
3. **Basic Selection**: Best match strategy only
4. **CLI Integration**: --template-collection flag

### **Phase 2: Advanced Selection**
1. **Ensemble Strategy**: Multiple template set verification
2. **Context Matching**: Tag-based template selection
3. **Performance Tracking**: Usage and success rate metrics

### **Phase 3: Management Tools**
1. **Template Analysis**: Quality assessment, performance reports
2. **Collection Optimization**: Redundancy removal, quality filtering
3. **Training Recommendations**: Suggest missing template types

### **Phase 4: Apple Watch Integration**
1. **Automatic Context Detection**: Motion state, time patterns
2. **Incremental Learning**: Add templates from successful sessions
3. **Template Aging**: Remove outdated or low-performing templates

## Expected Performance Impact

### **Benefits**
- **Higher Accuracy**: Context-appropriate templates improve detection
- **Robustness**: Multiple template sets handle edge cases
- **Personalization**: Rich template diversity captures user patterns
- **Adaptability**: System improves over time with more training data

### **Costs**  
- **Storage**: ~5x increase in template file size
- **Computation**: ~2-3x increase in verification time (ensemble mode)
- **Complexity**: More sophisticated template management required

### **Mitigation Strategies**
- **Quality Thresholding**: Remove low-performing template sets
- **Set Limits**: Maximum 5-10 template sets per collection
- **Smart Selection**: Use best-match by default, ensemble only when needed
- **Compression**: Efficient template storage formats

## Migration Path

1. **Backwards Compatibility**: Single template files still work
2. **Gradual Adoption**: Users can start with single templates, add more over time  
3. **Automatic Conversion**: Convert single templates to collection format
4. **Performance Monitoring**: Track detection improvements with multi-templates

This architecture provides a foundation for personalized, context-aware pinch detection that adapts to user behavior patterns and different usage scenarios.