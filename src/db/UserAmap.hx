package db;
import sys.db.Object;
import sys.db.Types;

enum Right{
	AmapAdmin;		//accès à l'admin d'amap
	ContractAdmin(?cid:Int);	//accès à la gestion de contrat
	Membership;		//accès a la gestion de adhérents
	Messages;		//accès à la messagerie
}

@:id(userId,amapId)
class UserAmap extends Object
{
	@:relation(amapId)
	public var amap : Amap;
	#if neko
	public var amapId : SInt;
	#end
	
	@:relation(userId)
	public var user : db.User;
	#if neko
	public var userId : SInt;
	#end
	
	//public var lastMemberShip : SNull<SDate>;
	public var rights : SNull<SData<Array<Right>>>;
	

	static var CACHE = new Map<String,db.UserAmap>();
	
	
	public static function get(user:User, amap:Amap, ?lock = false) {
		//SPOD doesnt cache elements with double primary key, so lets do it manually
		var c = CACHE.get(user.id + "-" + amap.id);
		if (c == null) {
			c = manager.select($user == user && $amap == amap, true/*lock*/);		
			CACHE.set(user.id + "-" + amap.id,c);
		}
		return c;	
	}	
	
	
	public function giveRight(r:Right) {
	
		if (hasRight(r)) return;
		if (rights == null) rights = [];
		//switch(r) {
			//case AmapAdmin:
		//}
		lock();
		rights.push(r);
		update();
		
	}
	
	public function removeRight(r:Right) {	
		if (rights == null) return;
		var newrights = [];
		for (right in rights.copy()) {
			if ( !Type.enumEq(right, r) ) {
				//App.log("remove "+r);
				//rights.remove(r);
				newrights.push(right);
			}
		}
		rights = newrights;
		
	}
	
	public function hasRight(r:Right):Bool {
		if (this.user.isAdmin()) return true;
		if (rights == null) return false;
		for ( right in rights) {
			if ( Type.enumEq(r,right) ) return true;
		}
		return false;
	}
	
	public function getRightName(r:Right):String {
		return switch(r) {
		case AmapAdmin : "Administrateur";
		case Messages : "Messagerie";
		case Right.Membership : "Gestion adhérents";
		case ContractAdmin(cid) : 
			if (cid == null) {
				"Gestion de tous les contrats";
			}else {
				"Gestion contrat : " + db.Contract.manager.get(cid).name;
			}
		}
	}
	
	
	/**
	 * Est ce que ce membre est a jour de sa cotisation
	 * @return
	 */
	public function hasValidMembership():Bool {
		
		if (amap.membershipRenewalDate == null) return false;
		

		var cotis = db.Membership.get(this.user, this.amap, this.amap.getMembershipYear());
		
		return cotis != null;

		////trouve la date la plus recente de renouvellement de cotisation
		//var lastRenewal = amap.membershipRenewalDate;
		//lastRenewal =  new Date(Date.now().getFullYear(), lastRenewal.getMonth(), lastRenewal.getDate(),0,0,0);
		//if (lastRenewal.getTime() > Date.now().getTime()) {
			//lastRenewal =  new Date(Date.now().getFullYear()-1, lastRenewal.getMonth(), lastRenewal.getDate(),0,0,0);
		//}
		//
		//return (lastMemberShip.getTime() > lastRenewal.getTime());
	}
	
	override public function insert(){
		
		App.current.event(NewMember(this.user,this.amap));
		
		super.insert();
	}
	
}