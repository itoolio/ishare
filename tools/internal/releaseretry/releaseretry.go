package releaseretry

import (
	"encoding/json"
	"fmt"
	"io"
)

const MaxAttempts = 3

type Step struct {
	Name       string `json:"name"`
	Conclusion string `json:"conclusion"`
}

type Job struct {
	Name       string `json:"name"`
	Conclusion string `json:"conclusion"`
	Steps      []Step `json:"steps"`
}

type Jobs struct {
	Jobs []Job `json:"jobs"`
}

type Decision struct {
	Retry  bool
	Reason string
}

func Parse(reader io.Reader) (Jobs, error) {
	var jobs Jobs
	if err := json.NewDecoder(reader).Decode(&jobs); err != nil {
		return Jobs{}, fmt.Errorf("reading the jobs: %w", err)
	}
	return jobs, nil
}

func Decide(jobs Jobs, attempt int) Decision {
	if attempt >= MaxAttempts {
		return Decision{Reason: fmt.Sprintf("attempt %d already reached the limit of %d", attempt, MaxAttempts)}
	}
	var lost []string
	for _, job := range jobs.Jobs {
		if !failed(job.Conclusion) {
			continue
		}
		if step := failedStep(job); step != "" {
			return Decision{Reason: fmt.Sprintf("%s failed in step %q, which is a real failure", job.Name, step)}
		}
		lost = append(lost, job.Name)
	}
	if len(lost) == 0 {
		return Decision{Reason: "no job failed"}
	}
	return Decision{Retry: true, Reason: fmt.Sprintf("%d job(s) stopped without a failing step, which looks like a lost runner: %v", len(lost), lost)}
}

func failed(conclusion string) bool {
	return conclusion == "failure" || conclusion == "cancelled" || conclusion == "timed_out"
}

func failedStep(job Job) string {
	for _, step := range job.Steps {
		if step.Conclusion == "failure" || step.Conclusion == "timed_out" {
			return step.Name
		}
	}
	return ""
}
