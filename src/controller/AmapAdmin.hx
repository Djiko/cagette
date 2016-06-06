package controller;
import db.UserAmap;
import haxe.Http;
import sugoi.Web;
import sugoi.form.Form;
import Common;
import sugoi.form.elements.IntSelect;
import sugoi.form.elements.StringInput;


class AmapAdmin extends Controller
{

	public function new() 
	{
		super();
		if (!app.user.isAmapManager()) throw Error("/", "Accès non autorisé");
		
		//lance un event pour demander aux plugins si ils veulent ajouter un item dans la nav
		var nav = new Array<Link>();
		var e = Nav(nav,"groupAdmin");
		app.event(e);
		view.nav = e.getParameters()[0];
	}
	
	
	@tpl("amapadmin/default.mtt")
	function doDefault() {
		view.membersNum = UserAmap.manager.count($amap == app.user.amap);
		view.contractsNum = app.user.amap.getActiveContracts().length;
		
		
		
		//ping cagette groups directory
		if (Std.random(10) == 0 && app.user.amap.flags.has(db.Amap.AmapFlags.CagetteNetwork)){
			
			var req = new Http("http://annuaire.cagette.net/api/ping?url="+StringTools.urlEncode( "http://" + App.config.HOST  ) );
			
			
			try{
				req.request();
			}catch (e:Dynamic){
				App.current.logError("Error while contacting annuaire.cagette.net : "+e);
			}
			
		}
		
	}
	
	@tpl("amapadmin/addimage.mtt")
	function doAddimage() {
		if (!app.user.isAmapManager()) throw "Vous n'avez pas accès a cette section";
		
		var user = app.user;
		view.image = user.amap.image;
		
		var request = new Map();
		try {
			request = sugoi.tools.Utils.getMultipart(1024 * 1024 * 12); //12Mb	
		}catch (e:Dynamic) {
			throw Error("/amapadmin", "L'image envoyée est trop lourde. Le poids maximum autorisé est de 12 Mo");
		}
		
		if (request.exists("image")) {
			
			//Image
			var image = request.get("image");
	
			if (image != null && image.length > 0) {
				
				var img : sugoi.db.File = null;
				if ( Sys.systemName() == "Windows") {
					img = sugoi.db.File.create(request.get("image"), request.get("image_filename"));
				}else {
					img = sugoi.tools.UploadedImage.resizeAndStore(request.get("image"), request.get("image_filename"), 400, 400);				
				}
				
				user.amap.lock();
				
				if (user.amap.image != null) {
					//delete previous file
					user.amap.image.lock();
					user.amap.image.delete();
				}
				
				user.amap.image = img;
				user.amap.update();
				
				throw Ok('/amapadmin/','Image mise à jour');
			}
		}
		
	}
	
	
	@tpl("amapadmin/rights.mtt")
	public function doRights() {
		
		//liste les gens qui ont des droits dans le groupe
		var users = db.UserAmap.manager.search($rights != null && $amap == app.user.amap, false);
		
		//cleaning 
		for ( u in Lambda.array(users)) {
			
			//rights peut etre null (null seralisé) et pas null en DB
			if (u.rights == null || u.rights.length == 0) {
				u.lock();
				Reflect.setField(u, "rights", null);
				u.update();
				users.remove(u);
				continue;
			}
			
			//droits sur un contrat effacé
			for ( r in u.rights) {
				switch(r) {
					case ContractAdmin(cid):
						if (cid == null) continue;
						var c = db.Contract.manager.get(cid);
						if (c == null) {
							u.lock();
							u.removeRight(r);
							u.update();
						}
					default :
				}
			}
		}
		
		view.users = users;

	}
	
	
	@tpl("form.mtt")
	public function doEditRight(?u:db.User) {
		
		var form = new sugoi.form.Form("editRight");
		
		if (u == null) {
			form.addElement( new IntSelect("user", "Adhérent", app.user.amap.getMembersFormElementData(), null, true) );	
		}
		
		var data = [];
		for (r in db.UserAmap.Right.getConstructors()) {
			if (r == "ContractAdmin") continue; //managed later
			data.push({label:r,value:r});
		}
		
		var ua : db.UserAmap = null;
		var populate :Array<String> = null;
		if (u != null) {
			ua = db.UserAmap.get(u, app.user.amap, true);
			if (ua == null) throw "no user";
			if (ua.rights == null) ua.rights = [];
			//populate form
			populate = ua.rights.map(function(x) return x.getName());
		}
		
		form.addElement( new sugoi.form.elements.CheckboxGroup("rights", "Droits", data, populate, true, true) );
		form.addElement( new sugoi.form.elements.Html("<hr/>"));
		
		//Rights on contracts
		var data = [];
		var populate :Array<String> = [];
		data.push({value:"contractAll",label:"Tous les contrats"});
		for (r in app.user.amap.getActiveContracts(true)) {
			data.push( { label:r.name , value:"contract"+Std.string(r.id) } );
		}
		
		if(ua!=null && ua.rights!=null){
			for ( r in ua.rights) {
				switch(r) {
					case Right.ContractAdmin(cid):
						if (cid == null) {
							populate.push("contractAll");
						}else {
							populate.push("contract"+cid);	
						}
						
					default://
				}
			}
		}
		

		form.addElement( new sugoi.form.elements.CheckboxGroup("rights", "Gestion contrats", data, populate, true, true) );
		
		if (form.checkToken()) {
			
			var wasManager = app.user.isAmapManager();
			
			if (u == null) {				
				ua = db.UserAmap.manager.select($userId == Std.parseInt(form.getValueOf("user")) && $amapId == app.user.amap.id, true);
			}
			ua.rights = [];

			var arr : Array<String> = cast form.getElement("rights").value;
			for ( r in arr) {
				if (r.substr(0, 8) == "contract") {
					if (r == "contractAll") {
						ua.rights.push( Right.ContractAdmin() );
					}else {
						ua.rights.push( Right.ContractAdmin(Std.parseInt(r.substr(8)) ) );	
					}
					
				}else {
					ua.rights.push( db.UserAmap.Right.createByName(r) );	
				}
			}
			
			//avoid "cut my own hands" problem
			if (ua.user.id == app.user.id && wasManager ) {
				var isManager = false;
				for ( r in ua.rights) {
					if (r.equals(db.UserAmap.Right.AmapAdmin)) {
						isManager = true; 
						break;
					}
				}
				if (isManager == false) {
					throw Error("/amapadmin/rights", "Par sécurité, vous ne pouvez pas vous enlevez vous même les droits de gestion du groupe.");
				}
			}
			
			
			if (ua.rights.length == 0) ua.rights = null;
			ua.update();
			if (ua.rights == null) {
				throw Ok("/amapadmin/rights", "Droits retirés");	
			}else {
				throw Ok("/amapadmin/rights", "Droits créés ou modifiés");
			}
			
		}
		
		if (u == null) {
			view.title = "Créer des droits à un utilisateur";
		}else {
			view.title = "Modifier les droits de "+u.getName();
		}
		
		view.form = form;
		
	}
	
	@tpl('form.mtt')
	public function doVatRates() {
		
		var f = new sugoi.form.Form("vat");
		var a = app.user.amap;
		
		if (a.vatRates == null) {
			a.lock();
			var x = new db.Amap();
			a.vatRates = x.vatRates;
			a.update();
		}
		
		var i = 1;
		for (k in a.vatRates.keys()) {
			f.addElement(new StringInput(i+"-k", "Nom "+i, k));
			f.addElement(new StringInput(i + "-v", "Taux "+i, Std.string(a.vatRates.get(k)) ));
			//f.addElement(new sugoi.form.elements.Html("<hr/>"));
			i++;
		}
		var j = i;
		
		for (x in 0...5 - i) {
			f.addElement(new StringInput(i+"-k", "Nom "+i, ""));
			f.addElement(new StringInput(i + "-v", "Taux "+i, ""));
			//f.addElement(new sugoi.form.elements.Html("<hr/>"));
			i++;
		}
		
		if (f.isValid()) {
			var d = f.getData();
			var vats = new Map<String,Float>();
			var filter = new sugoi.form.filters.FloatFilter();
			for (i in 1...5) {
				if (d.get(i + "-k") == null) continue;
				vats.set(d.get(i + "-k"), filter.filter( d.get(i + "-v")) );
			}
			a.lock();
			a.vatRates = vats;
			a.update();
			throw Ok("/amapadmin", "Taux mis à jour");
			
		}
		view.title = "Editer les taux de TVA";
		view.form = f;
		
	}
	
	function doCategories(d:haxe.web.Dispatch) {
		d.dispatch(new controller.Categories());
	}	
	
	
}