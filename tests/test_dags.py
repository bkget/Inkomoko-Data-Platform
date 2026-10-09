import unittest

try:
    from airflow.models import DagBag
except ImportError:
    DagBag = None


@unittest.skipIf(DagBag is None, "airflow is not installed in this environment")
class TestAirflowDags(unittest.TestCase):
    """Ensure every DAG in airflow_dag/ imports without errors."""

    def setUp(self):
        self.dagbag = DagBag(dag_folder="airflow_dag", include_examples=False)

    def test_no_import_errors(self):
        self.assertFalse(self.dagbag.import_errors, msg=self.dagbag.import_errors)

    def test_inkomoko_pipeline_present(self):
        self.assertIn("inkomoko_kiva_pipeline", self.dagbag.dags)

    def test_pipeline_has_cdc_gate_between_ingest_and_dbt(self):
        """Lineage must flow ingest -> CDC catch-up gate -> dbt."""
        dag = self.dagbag.dags.get("inkomoko_kiva_pipeline")
        if dag is None:
            self.skipTest("pipeline DAG not present")
        ingest = dag.get_task("ingest_kiva_api_to_postgres")
        wait_for_cdc = dag.get_task("wait_for_cdc_catch_up")
        dbt = dag.get_task("dbt_analytics_models")
        self.assertEqual(list(ingest.downstream_task_ids), ["wait_for_cdc_catch_up"])
        self.assertEqual(list(wait_for_cdc.downstream_task_ids), ["dbt_analytics_models"])
        self.assertEqual(set(dbt.upstream_task_ids), {"wait_for_cdc_catch_up"})


if __name__ == "__main__":
    unittest.main()
