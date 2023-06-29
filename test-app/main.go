package main

import (
	_ "embed"
	"html/template"
	"log"
	"net/http"
	"os"
	"sort"
	"strings"
)

//go:embed index.tmpl
var indexTemplate string

type EnvironmentVariable struct {
	Key   string
	Value string
}

func main() {
	tmpl, err := template.New("index").Parse(indexTemplate)
	if err != nil {
		log.Fatal(err)
	}

	http.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		var (
			environmentVariables       = os.Environ()
			environmentVariableStructs []EnvironmentVariable
		)

		sort.Strings(environmentVariables)

		for _, env := range environmentVariables {
			key, value, _ := strings.Cut(env, "=")
			environmentVariableStructs = append(environmentVariableStructs, EnvironmentVariable{
				Key:   key,
				Value: value,
			})
		}

		if err := tmpl.Execute(w, environmentVariableStructs); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	})

	log.Println("listening on :7777")

	if err := http.ListenAndServe(":7777", nil); err != nil {
		log.Fatal(err)
	}
}
