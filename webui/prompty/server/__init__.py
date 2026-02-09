"""
PromptyUI Server Package

Provides API endpoints for the PromptyUI UI.

API Endpoints (all prefixed with /api/pu/):
    GET  /api/pu/jobs              - List all jobs from jobs/ folder
    GET  /api/pu/job/{job_id}      - Get job details (parsed jobs.yaml)
    GET  /api/pu/extensions        - List extensions tree from ext/ folder
    GET  /api/pu/extension/{path}  - Get extension file content
    POST /api/pu/preview           - Preview resolved variations
    POST /api/pu/export            - Export job to jobs.yaml
    POST /api/pu/validate          - Validate job configuration
"""

from .app import create_app, main

__all__ = ['create_app', 'main']
