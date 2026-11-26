import 'package:flutter/material.dart';
import '../../core/services/build_history_store.dart';
import '../../core/services/file_version_history.dart';
import '../../core/services/editor_quick_fix_engine.dart';

Future<void> showAdvancedSearchSheet(BuildContext context, {required String fileName, required String text, required void Function(int,int) onJump, required ValueChanged<String> onReplace}) async {
 final find=TextEditingController(), replace=TextEditingController();
 await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(ctx)=>StatefulBuilder(builder:(ctx,setSheet){
  final q=find.text; final hits=<int>[];
  if(q.isNotEmpty){var p=0;while(p<=text.length-q.length){final i=text.indexOf(q,p);if(i<0)break;hits.add(i);p=i+q.length;}}
  return Padding(padding:EdgeInsets.fromLTRB(16,16,16,MediaQuery.of(ctx).viewInsets.bottom+16),child:Column(mainAxisSize:MainAxisSize.min,children:[
   Text('بحث متقدم · $fileName'),TextField(controller:find,decoration:const InputDecoration(labelText:'بحث'),onChanged:(_)=>setSheet((){})),
   TextField(controller:replace,decoration:const InputDecoration(labelText:'استبدال بـ')),
   Text('النتائج: ${hits.length}'),
   SizedBox(height:160,child:ListView.builder(itemCount:hits.length,itemBuilder:(_,i)=>ListTile(title:Text('نتيجة ${i+1} · السطر ${text.substring(0,hits[i]).split('\n').length}'),onTap:(){onJump(hits[i],hits[i]+q.length);Navigator.pop(ctx);}))),
   Row(children:[Expanded(child:TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إغلاق'))),Expanded(child:FilledButton(onPressed:hits.isEmpty?null:(){onReplace(text.replaceAll(q,replace.text));Navigator.pop(ctx);},child:const Text('استبدال الكل')))])
  ]));
 }));
 find.dispose();replace.dispose();
}
String _tidy(String s){final a=s.replaceAll('\r\n','\n').replaceAll('\r','\n').split('\n').map((x)=>x.replaceFirst(RegExp(r'[ \t]+$'),'')).toList();while(a.isNotEmpty&&a.last.isEmpty){a.removeLast();}return a.isEmpty?'':'${a.join('\n')}\n';}
Future<void> showFixAssistantSheet(
  BuildContext context, {
  required String fileName,
  required String source,
  required String language,
  required ValueChanged<String> onApply,
}) async {
  final preview = EditorQuickFixEngine.preview(source, language);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('مساعد الإصلاح · $fileName',
            style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'يقترح إصلاح الأقواس غير المتطابقة عندما يكون التعديل واضحًا، '
            'مع تنظيف المسافات ونهايات الأسطر. راجع المعاينة قبل التطبيق.',
          ),
          const SizedBox(height: 10),
          if (preview.fixes.isEmpty)
            const Text('لا توجد إصلاحات آمنة مقترحة.')
          else
            ...preview.fixes.map((fix) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF34D399)),
                const SizedBox(width: 7),
                Expanded(child: Text(fix, style: const TextStyle(fontSize: 12))),
              ]),
            )),
          const SizedBox(height: 10),
          Container(
            height: 170,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF26374E)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                preview.updatedSource,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            )),
            Expanded(child: FilledButton(
              onPressed: preview.hasChanges
                  ? () {
                      onApply(preview.updatedSource);
                      Navigator.pop(ctx);
                    }
                  : null,
              child: const Text('تطبيق الإصلاحات'),
            )),
          ]),
        ],
      ),
    ),
  );
}
Future<void> showFormatPreviewSheet(BuildContext context,{required String fileName,required String source,required String language,required ValueChanged<String> onApply}) async {
 final v=_tidy(source);await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(ctx)=>Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
 Text('معاينة التنسيق · $fileName'),Text('تنسيق آمن للمسافات ونهايات الأسطر · $language'),
 SizedBox(height:260,child:SingleChildScrollView(child:SelectableText(v,style:const TextStyle(fontFamily:'monospace')))),
 Row(children:[Expanded(child:TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('إلغاء'))),Expanded(child:FilledButton(onPressed:v==source?null:(){onApply(v);Navigator.pop(ctx);},child:const Text('اعتماد')))])
 ])));
}
Future<void> showVersionHistorySheet(BuildContext context,{required FileVersionHistory history,required String historyKey,required String fileName,required String currentText,required ValueChanged<String> onRestore}) async {
 final items=await history.list(historyKey);if(!context.mounted)return;
 await showModalBottomSheet<void>(context:context,useSafeArea:true,builder:(ctx)=>SizedBox(height:MediaQuery.of(ctx).size.height*.65,child:Column(children:[
 Padding(padding:const EdgeInsets.all(16),child:Text('سجل الإصدارات · $fileName')),
 Expanded(child:items.isEmpty?const Center(child:Text('لا توجد نسخ محفوظة بعد.')):ListView.builder(itemCount:items.length,itemBuilder:(_,i){final e=items[i];return ListTile(leading:const Icon(Icons.history),title:Text(e['label']?.toString()??'نسخة محفوظة'),subtitle:Text(e['createdAt']?.toString()??''),onTap:(){onRestore(e['content']?.toString()??'');Navigator.pop(ctx);});}))
 ])));
}
Future<void> showBuildAnalysisSheet(BuildContext context,{required String log,required BuildHistoryStore? store}) async {
 final items=await store?.recent()??[];if(!context.mounted)return;
 await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(ctx)=>SizedBox(height:MediaQuery.of(ctx).size.height*.72,child:Column(children:[
 Padding(padding:const EdgeInsets.all(16),child:Text('تحليل وسجل البناء',style:Theme.of(ctx).textTheme.titleMedium)),
 Expanded(flex:2,child:SingleChildScrollView(padding:const EdgeInsets.all(12),child:SelectableText(log.isEmpty?'لا يوجد سجل بناء حالي.':log,style:const TextStyle(fontFamily:'monospace',fontSize:11)))),
 const Divider(),Text('عمليات البناء السابقة: ${items.length}'),
 Expanded(child:items.isEmpty?const Center(child:Text('لا توجد عمليات محفوظة.')):ListView.builder(itemCount:items.length,itemBuilder:(_,i){final e=items[i];return ListTile(leading:Icon(e['success']==true?Icons.check_circle:Icons.error_outline),title:Text(e['projectName']?.toString()??'مشروع'),subtitle:Text('${e['mode']??''} · ${e['createdAt']??''}'),onTap:()=>showDialog<void>(context:ctx,builder:(d)=>AlertDialog(title:const Text('سجل البناء'),content:SizedBox(width:double.maxFinite,height:300,child:SingleChildScrollView(child:SelectableText(e['log']?.toString()??''))),actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('إغلاق'))])));}))
 ])));
}
