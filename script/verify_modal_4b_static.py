"""Source-only verification: no model downloads or network inference."""
import ast
import importlib.util
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
expected={
 'qwen3_embedding_service':('Qwen/Qwen3-Embedding-4B','5cf2132abc99cad020ac570b19d031efec650f2b'),
 'qwen3_reranker_service':('Qwen/Qwen3-Reranker-4B','22e683669bc0f0bd69640a1354a6d0aebcfeede5'),
}
items=[]
for name,(model,revision) in expected.items():
 path=root/'modal_app'/(name+'.py')
 tree=ast.parse(path.read_text(encoding='utf-8'))
 s=importlib.util.spec_from_file_location(name,path)
 m=importlib.util.module_from_spec(s)
 s.loader.exec_module(m)
 assert m.MODEL_ID==model and m.MODEL_REVISION==revision and len(revision)==40
 assert any(isinstance(node,ast.FunctionDef) for node in tree.body)
 items.append({'source':name,'model_id':model,'revision':revision,'static_import':'PASS'})
assert items[0]['model_id']!=items[1]['model_id']
print(json.dumps({'status':'PASS_SOURCE_ONLY','modal_sdk_imports':items,
 'models_downloaded':False,'gpu_executed':False},indent=2))
