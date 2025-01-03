---
name: Bug Report
about: Create a detailed bug report to help improve Spatial Tag
title: '[BUG] '
labels: bug, needs-triage
assignees: ''
---

## Bug Description
### Summary
<!-- Provide a clear and concise description of the bug -->

### Expected Behavior
<!-- Describe what you expected to happen -->

### Actual Behavior
<!-- Describe what actually happened -->

### Impact Level
- [ ] Critical - Service Outage
- [ ] High - Feature Unusable
- [ ] Medium - Feature Degraded
- [ ] Low - Minor Issue

## System Information
### iOS Client Details
- Device Model: 
- iOS Version: 
- App Version: 
- LiDAR Capability Status: 
- Battery Level: 
- Available Storage: 
- Network Connection Type: 

### Backend Service Details
- API Version: 
- Service Name: 
- Environment: 
- Region: 
- Deployment Version: 

## Technical Details
### LiDAR Metrics
| Metric | Value | Expected Range |
|--------|--------|---------------|
| Scanning Range | | 0.5m - 50m |
| Refresh Rate | | ≥30Hz |
| Precision Level | | ±1cm at 10m |
| Power Usage | | ~0.8W |
| Field of View | | 120° horizontal |

### Performance Metrics
| Metric | Value | Target |
|--------|--------|--------|
| Response Time | | <100ms |
| Battery Drain Rate | | <15%/hour |
| Memory Usage | | |
| CPU Usage | | |
| Network Latency | | |

### Error Data
#### Error Code
```
<!-- Insert error code here -->
```

#### Stack Trace
```
<!-- Insert stack trace here -->
```

#### Log Snippets
```
<!-- Insert relevant log snippets here -->
```

#### Crash Reports
```
<!-- Insert crash reports if applicable -->
```

## Steps to Reproduce
1. 
2. 
3. 

## Additional Context
<!-- Add any other relevant context about the problem here -->

### Screenshots/Recordings
<!-- Attach screenshots or recordings if applicable -->

### Device Logs
<!-- Attach relevant device logs if available -->

## Environment Impact
- [ ] Development
- [ ] Staging
- [ ] Production
- [ ] All Environments

## Suggested Labels
<!-- Check all that apply -->
- [ ] ios-client
- [ ] backend
- [ ] spatial-engine
- [ ] performance
- [ ] lidar
- [ ] ar

## Team Assignment
<!-- Check the primary team needed -->
- [ ] iOS Team
- [ ] Backend Team
- [ ] DevOps Team
- [ ] QA Team
- [ ] SRE Team

---
<!-- 
Before submitting:
1. Ensure all required sections are completed
2. Include LiDAR metrics for AR/spatial issues
3. Include performance metrics
4. Attach screenshots for UI issues
5. Check appropriate labels and assignments
-->