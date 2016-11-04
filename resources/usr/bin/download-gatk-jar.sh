#!/bin/bash

set -e -o pipefail

dx find data --project $DX_PROJECT_CONTEXT_ID --class file --name "GenomeAnalysisTK*.jar" --json --state closed >.jarfiles.json
jq length <.jarfiles.json >.jarfiles.length
if [[ $(<.jarfiles.length) == 0 ]]; then
  dx-jobutil-report-error "Could not locate GenomeAnalysisTK*.jar inside the project. This app is only a wrapper, and requires that you appropriately license and obtain the GATK software yourself. See the app help for more info."
fi
if [[ $(<.jarfiles.length) != 1 ]]; then
  dx-jobutil-report-error "Too many GenomeAnalysisTK*.jar files located inside the project. You must have exactly one GATK version for this app to use."
fi
jq -r '.[0].id' <.jarfiles.json >.jarfile.id
dx download $(<.jarfile.id) -o GenomeAnalysisTK.jar
if ! java -jar GenomeAnalysisTK.jar --version; then
  dx-jobutil-report-error "Error using the supplied GenomeAnalysisTK*.jar file. Are you sure this is a GATK3 jar file?"
fi

